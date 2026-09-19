import Foundation
import AppKit
import OpenIslandCore
import Observation

@Observable
final class EcosystemSignalsState {
    var automationIsRunning: Bool = false
    var jobSummary: MitamaJobSummary?
    var codexFailures: [String: CodexFailure] = [:]
}

final class EcosystemSignalsCoordinator {
    let workLog: MitamaWorkLogClient
    let state: EcosystemSignalsState

    private var automationProbeTask: Task<Void, Never>?
    private var codexGateTask: Task<Void, Never>?

    init(workLog: MitamaWorkLogClient, state: EcosystemSignalsState = EcosystemSignalsState()) {
        self.workLog = workLog
        self.state = state
    }

    func start() {
        startAutomationProbe()
        startCodexGateMonitoring()
    }

    func stop() {
        automationProbeTask?.cancel()
        codexGateTask?.cancel()
    }

    func updateJobSummaryFromFeed() {
        Task {
            let summary = await self.workLog.jobSummary()
            await MainActor.run {
                self.state.jobSummary = summary
            }
        }
    }

    private func startAutomationProbe() {
        automationProbeTask = Task {
            while !Task.isCancelled {
                let isRunning = await probeAutomation()
                await MainActor.run { [weak self] in
                    self?.state.automationIsRunning = isRunning
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func probeAutomation() async -> Bool {
        guard let browserPID = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == "com.mitama.browser" })?
            .processIdentifier else { return false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP@127.0.0.1:9222", "-sTCP:ESTABLISHED"]

        let pipe = Pipe()
        process.standardOutput = pipe

        guard (try? process.run()) != nil else { return false }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return false }

        process.waitUntilExit()

        return BrowserAutomationProbe.isDriven(lsofOutput: output, browserPID: browserPID)
    }

    private func startCodexGateMonitoring() {
        codexGateTask = Task {
            while !Task.isCancelled {
                let path = NSHomeDirectory() + "/.claude/analytics/codex-findings.jsonl"
                if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                   let content = String(data: data, encoding: .utf8) {
                    let lines = content.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
                    let tail = Array(lines.suffix(200))
                    let failures = CodexGateLog.latestFailure(lines: tail, now: .now, window: 24 * 3600)

                    await MainActor.run { [weak self] in
                        self?.state.codexFailures = failures
                    }
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
}
