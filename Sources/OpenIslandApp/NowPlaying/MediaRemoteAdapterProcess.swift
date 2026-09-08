import Foundation

/// Incrementally splits a byte stream into complete newline-delimited lines,
/// buffering whatever hasn't seen a newline yet. Kept separate from the
/// `Process`/`Pipe` wiring below so it can be tested by feeding it raw byte
/// chunks instead of standing up a real perl subprocess.
struct NDJSONLineSplitter {
    private var buffer = Data()
    private static let newline = UInt8(ascii: "\n")

    /// Appends `data` and returns every complete line it now completes,
    /// oldest first. A line with no bytes (two newlines back to back) is
    /// dropped rather than reported — the adapter never sends one on
    /// purpose, and a decoder further down would just reject it anyway.
    mutating func feed(_ data: Data) -> [String] {
        buffer.append(data)

        var lines: [String] = []
        while let newlineIndex = buffer.firstIndex(of: Self.newline) {
            let lineData = buffer.prefix(upTo: newlineIndex)
            buffer.removeSubrange(...newlineIndex)
            guard !lineData.isEmpty, let line = String(data: lineData, encoding: .utf8) else { continue }
            lines.append(line)
        }
        return lines
    }
}

/// Runs `mediaremote-adapter.pl stream` (ungive/mediaremote-adapter,
/// BSD-3-Clause) as a child process and turns its NDJSON output into
/// `(payload, diff)` pairs for `NowPlayingCoordinator` to fold through
/// `NowPlayingReducer`. See docs/references/mediaremote-adapter.md for why
/// this exists instead of talking to `MediaRemote.framework` directly.
///
/// `@unchecked Sendable`, same reasoning as `CodexAppServerClient`:
/// `Pipe.readabilityHandler` and `Process.terminationHandler` are
/// `@Sendable`-typed, so capturing `self` in either requires the class to
/// conform. Every mutation happens sequentially through this one process's
/// own lifecycle (launch → read/terminate → scheduled relaunch), never
/// concurrently with itself.
final class MediaRemoteAdapterProcess: @unchecked Sendable {
    struct Update {
        let payload: [String: Any]
        let diff: Bool
    }

    /// MediaRemote command IDs the adapter's `send` subcommand accepts.
    /// Only the ones the opened surface's transport controls use.
    enum Command: Int {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    /// Fires once at `start()` (or whenever a relaunch changes the answer):
    /// `true` once the child process is actually running, `false` when
    /// there's no framework/perl to run it with at all. Does *not* fire on
    /// every restart attempt after a crash — those retry silently.
    var onAvailabilityChange: ((Bool) -> Void)?
    var onUpdate: ((Update) -> Void)?

    private let frameworkPath: String?
    private let perlPath: String
    private let perlScriptPath: String?

    private var process: Process?
    private var splitter = NDJSONLineSplitter()
    private var restartAttempt = 0
    private var restartTask: Task<Void, Never>?
    private var stopped = true

    init(
        frameworkPath: String? = MediaRemoteAdapterProcess.resolveFrameworkPath(),
        perlScriptPath: String? = MediaRemoteAdapterProcess.resolvePerlScriptPath(),
        perlPath: String = "/usr/bin/perl"
    ) {
        self.frameworkPath = frameworkPath
        self.perlScriptPath = perlScriptPath
        self.perlPath = perlPath
    }

    /// Whether the pieces needed to even attempt launching are present —
    /// not whether the OS will actually grant Perl the MediaRemote
    /// entitlement, which can only be found out by trying.
    var isAvailable: Bool {
        frameworkPath != nil && perlScriptPath != nil && FileManager.default.fileExists(atPath: perlPath)
    }

    func start() {
        stopped = false
        restartAttempt = 0
        launch()
    }

    func stop() {
        stopped = true
        restartTask?.cancel()
        restartTask = nil
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
    }

    func send(_ command: Command) {
        runControlCommand(["send", String(command.rawValue)])
    }

    func seek(toMicroseconds micros: Int) {
        runControlCommand(["seek", String(max(0, micros))])
    }

    // MARK: - Callback dispatch

    /// `readabilityHandler` and `terminationHandler` fire on Foundation's own
    /// dispatch queues, never the main queue. `NowPlayingCoordinator` (the
    /// only real caller) is `@MainActor` and relies on these callbacks
    /// actually arriving on the main queue — the same
    /// `queue: .main`-then-`MainActor.assumeIsolated` shape
    /// `FocusTimerCoordinator`'s wake observer uses — so every callback is
    /// hopped here rather than trusting each call site to remember to.
    private func notifyAvailability(_ available: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.onAvailabilityChange?(available)
        }
    }

    private func notifyUpdate(_ update: Update) {
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(update)
        }
    }

    // MARK: - Launching the stream

    private func launch() {
        guard let frameworkPath, let perlScriptPath else {
            notifyAvailability(false)
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: perlPath)
        proc.arguments = [perlScriptPath, frameworkPath, "stream"]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe
        proc.standardInput = FileHandle.nullDevice

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.handleIncomingData(data)
        }
        // Every stderr line is documented as non-fatal unless the process
        // also exits non-zero — draining it just keeps a full pipe from
        // blocking the child.
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        proc.terminationHandler = { [weak self] _ in
            self?.handleTermination()
        }

        process = proc
        do {
            try proc.run()
            notifyAvailability(true)
        } catch {
            process = nil
            notifyAvailability(false)
            scheduleRestart()
        }
    }

    private func handleIncomingData(_ data: Data) {
        for line in splitter.feed(data) {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let payload = json["payload"] as? [String: Any] else {
                continue
            }
            let diff = (json["diff"] as? Bool) ?? true
            notifyUpdate(Update(payload: payload, diff: diff))
        }
    }

    private func handleTermination() {
        process = nil
        guard !stopped else { return }
        scheduleRestart()
    }

    /// Exponential backoff, capped at 30s — a crash loop must not spin the
    /// CPU, but a transient failure (e.g. right after a macOS update swaps
    /// out MediaRemote's entitlement checks) should recover on its own
    /// within a reasonable time.
    private func scheduleRestart() {
        restartAttempt += 1
        let delaySeconds = min(30.0, pow(2.0, Double(restartAttempt)))
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delaySeconds))
            guard let self, !Task.isCancelled, !self.stopped else { return }
            self.launch()
        }
    }

    // MARK: - One-shot control commands

    /// `send`/`seek` are fire-and-forget, single-shot invocations of the
    /// same perl script — no relationship to the long-lived `stream`
    /// process, and safe to call even while it isn't running.
    private func runControlCommand(_ args: [String]) {
        guard let frameworkPath, let perlScriptPath else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: perlPath)
        proc.arguments = [perlScriptPath, frameworkPath] + args
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
    }

    // MARK: - Path resolution

    /// `OPEN_ISLAND_MEDIAREMOTE_FRAMEWORK` override → a signed app's own
    /// `Contents/Frameworks/` → the vendored dev build fetched by
    /// `scripts/fetch-mediaremote-adapter.sh`, searched for by walking up
    /// from wherever `swift run` placed the executable.
    static func resolveFrameworkPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        let fileManager = FileManager.default

        if let overridden = environment["OPEN_ISLAND_MEDIAREMOTE_FRAMEWORK"],
           fileManager.fileExists(atPath: overridden) {
            return overridden
        }

        let bundled = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Frameworks/MediaRemoteAdapter.framework")
        if fileManager.fileExists(atPath: bundled.path) {
            return bundled.path
        }

        var candidateDirectory = Bundle.main.bundleURL
        for _ in 0..<6 {
            let candidate = candidateDirectory
                .appendingPathComponent("vendor/mediaremote-adapter/build/MediaRemoteAdapter.framework")
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate.path
            }
            candidateDirectory = candidateDirectory.deletingLastPathComponent()
        }

        return nil
    }

    static func resolvePerlScriptPath() -> String? {
        Bundle.appResources.url(
            forResource: "mediaremote-adapter",
            withExtension: "pl",
            subdirectory: "MediaRemoteAdapter"
        )?.path
            ?? Bundle.appResources.url(forResource: "mediaremote-adapter", withExtension: "pl")?.path
    }
}
