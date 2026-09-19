import AppKit
import Foundation
import Observation
import OpenIslandCore

/// The three mitama-ecosystem signals the island surfaces, as plain state the
/// views read. Nothing here decides anything — the rules live in
/// `OpenIslandCore` (`BrowserAutomationProbe`, `BrowserAutomationActivity`,
/// `CodexGateLog`) so they can be tested without a browser, a socket, or a
/// file on disk.
@Observable
@MainActor
final class EcosystemSignalsState {
    /// mitama Browser has a CDP client attached — something is driving it.
    var automationIsRunning: Bool = false
    /// The last page that was navigated with nobody looking at it.
    var automationActivity: BrowserAutomationActivity?
    /// Projects whose newest Codex gate run failed, newest failure per project.
    var codexFailures: [String: CodexFailure] = [:]

    var codexFailure: CodexFailure? {
        codexFailures.values.max { $0.timestamp < $1.timestamp }
    }
}

/// Polls the two local signals: whether mitama Browser is being driven, and
/// whether the Codex quality gate is failing. The job queue is not polled
/// here — `MitamaFeedCoordinator` already talks to that database on its own
/// loop, and a second timer would double the traffic for the same answer.
@MainActor
final class EcosystemSignalsCoordinator {
    /// mitama Browser's bundle identifier. Its DevTools port is the one the
    /// probe looks at; without the PID a listening socket of the browser
    /// itself would read as a client.
    static let browserBundleID = "dev.mitama.browser"
    /// Nothing is polled for the first few seconds of a launch. The island's
    /// first job is to be on screen when a bridge notification arrives (there
    /// is a 200ms budget for that, and a test that guards it); forking `lsof`
    /// while that is happening is exactly the kind of work that eats it.
    private static let warmUp: TimeInterval = 3
    private static let automationInterval: TimeInterval = 5
    private static let codexInterval: TimeInterval = 30
    /// Only the tail matters, and the log grows for the life of the machine.
    nonisolated private static let codexTailBytes = 64 * 1024

    let state = EcosystemSignalsState()

    private var automationTask: Task<Void, Never>?
    private var codexTask: Task<Void, Never>?

    var automationEnabled = true {
        didSet { applyEnablement() }
    }

    var codexEnabled = true {
        didSet { applyEnablement() }
    }

    func start() {
        applyEnablement()
    }

    func stop() {
        automationTask?.cancel()
        automationTask = nil
        codexTask?.cancel()
        codexTask = nil
        state.automationIsRunning = false
        state.automationActivity = nil
        state.codexFailures = [:]
    }

    private func applyEnablement() {
        if automationEnabled, automationTask == nil {
            automationTask = Task { [weak self] in await self?.pollAutomation() }
        } else if !automationEnabled, automationTask != nil {
            automationTask?.cancel()
            automationTask = nil
            state.automationIsRunning = false
            state.automationActivity = nil
        }

        if codexEnabled, codexTask == nil {
            codexTask = Task { [weak self] in await self?.pollCodexGate() }
        } else if !codexEnabled, codexTask != nil {
            codexTask?.cancel()
            codexTask = nil
            state.codexFailures = [:]
        }
    }

    // MARK: - Automation

    private func pollAutomation() async {
        try? await Task.sleep(for: .seconds(Self.warmUp))
        while !Task.isCancelled {
            let pid = NSWorkspace.shared.runningApplications
                .first { $0.bundleIdentifier == Self.browserBundleID }?
                .processIdentifier
            let running: Bool
            if let pid {
                let output = await Task.detached(priority: .utility) {
                    Self.lsofOutput()
                }.value
                running = BrowserAutomationProbe.isDriven(lsofOutput: output, browserPID: pid)
            } else {
                running = false
            }

            let activity = running
                ? await Task.detached(priority: .utility) { Self.readActivity() }.value
                : nil

            guard !Task.isCancelled else { return }
            state.automationIsRunning = running
            state.automationActivity = activity

            try? await Task.sleep(for: .seconds(Self.automationInterval))
        }
    }

    /// `lsof` on one port. Off the main actor — it forks a process, and the
    /// island must not stutter for it.
    nonisolated private static func lsofOutput() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP@127.0.0.1:9222", "-sTCP:ESTABLISHED"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return ""
        }
        // Read before waiting: a full pipe buffer would deadlock the child.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    nonisolated private static func readActivity() -> BrowserAutomationActivity? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/mitama Browser/automation-activity.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return BrowserAutomationActivity.parse(data, now: .now)
    }

    // MARK: - Codex gate

    private func pollCodexGate() async {
        try? await Task.sleep(for: .seconds(Self.warmUp))
        while !Task.isCancelled {
            let lines = await Task.detached(priority: .utility) { Self.codexTailLines() }.value
            let failures = CodexGateLog.latestFailure(lines: lines, now: .now)
            guard !Task.isCancelled else { return }
            state.codexFailures = failures
            try? await Task.sleep(for: .seconds(Self.codexInterval))
        }
    }

    /// The last 64 KB of the log, split into whole lines. Reading the whole
    /// file would grow without bound; the first (possibly partial) line of
    /// the window is dropped rather than parsed half-way.
    nonisolated private static func codexTailLines() -> [String] {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/analytics/codex-findings.jsonl")
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return [] }
        let offset = size > UInt64(codexTailBytes) ? size - UInt64(codexTailBytes) : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return [] }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        if offset > 0, !lines.isEmpty { lines.removeFirst() }
        return lines
    }

    /// The P1 excerpt the gate saved next to the log entry. Read only when
    /// the owner asks for it, and capped — this is a display string, not a file.
    nonisolated static func codexExcerpt(at path: String, limit: Int = 4000) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return String(text.prefix(limit))
    }
}
