import Foundation
import Testing
@testable import OpenIslandCore

/// Two islands registered against the same events race each other on every
/// permission request, and the loser's answer is discarded. A fork the user
/// stopped running keeps its rows forever, because only installing strips them.
struct StrayIslandHookTests {
    private let ours = ClaudeHookInstaller.hookCommand(for: "/Applications/Mitama Island.app/Contents/Helpers/OpenIslandHooks")

    private func settings(_ commandsByEvent: [String: [String]]) -> Data {
        var hooks: [String: Any] = [:]
        for (event, commands) in commandsByEvent {
            hooks[event] = commands.map { ["hooks": [["type": "command", "command": $0]]] }
        }
        return try! JSONSerialization.data(withJSONObject: ["hooks": hooks])
    }

    private var vibeCommand: String {
        #"/bin/sh -c '[ -x "$HOME/.vibe-island/bin/vibe-island-bridge" ] && "$HOME/.vibe-island/bin/vibe-island-bridge" --source claude; exit 0'"#
    }

    @Test
    func anotherIslandIsFound() {
        let data = settings(["PermissionRequest": [ours, vibeCommand]])
        #expect(ClaudeHookInstaller.strayIslandHookCommands(in: data, excluding: ours) == [vibeCommand])
    }

    /// Our own rows are the point of the file — flagging them would ask the
    /// user to delete the very hooks the island runs on.
    @Test
    func ourOwnHooksAreNotStray() {
        let data = settings(["Stop": [ours], "PreToolUse": [ours]])
        #expect(ClaudeHookInstaller.strayIslandHookCommands(in: data, excluding: ours).isEmpty)
    }

    /// Everyone else's hooks stay untouched. This walks the same settings.json
    /// the user's other tooling lives in, so a false positive deletes their work.
    @Test
    func unrelatedHooksAreLeftAlone() {
        let data = settings([
            "PreToolUse": ["/Users/x/.claude/hooks/mitama-t3-gate.sh", #"node "/Users/x/.claude/hooks/gsd-prompt-guard.js""#],
            "Stop": ["/Users/x/.claude/hooks/codex-review-gate.sh"],
        ])
        #expect(ClaudeHookInstaller.strayIslandHookCommands(in: data, excluding: ours).isEmpty)
    }

    /// Events the island does not manage still get cleared, because installing
    /// rewrites every key it finds — and a row nobody runs is just latency.
    @Test
    func straysAreFoundOnUnmanagedEventsToo() {
        let data = settings(["TeammateIdle": [vibeCommand], "PostCompact": [vibeCommand]])
        #expect(ClaudeHookInstaller.strayIslandHookCommands(in: data, excluding: ours) == [vibeCommand])
    }

    /// Installing is what actually clears them; the diagnostics button just
    /// runs it. If this stopped being true the button would be a no-op.
    @Test
    func installingClearsThem() throws {
        let before = settings(["PermissionRequest": [vibeCommand], "TeammateIdle": [vibeCommand]])
        let mutation = try ClaudeHookInstaller.installSettingsJSON(existingData: before, hookCommand: ours)
        let after = try #require(mutation.contents)
        #expect(ClaudeHookInstaller.strayIslandHookCommands(in: after, excluding: ours).isEmpty)
    }

    @Test func installedManagedHelperIsNotAnotherIslandWhenBundleHelperIsResolved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let managed = directory.appendingPathComponent("Application Support/OpenIsland/bin/OpenIslandHooks")
        let bundle = directory.appendingPathComponent("Mitama Island.app/Contents/Helpers/OpenIslandHooks")
        // The name promises a resolved bundle helper; without the file the check
        // falls back to whatever helper this machine happens to have installed.
        for helper in [managed, bundle] {
            try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
            #expect(FileManager.default.createFile(atPath: helper.path, contents: Data(), attributes: [.posixPermissions: 0o755]))
        }
        let managedCommand = ClaudeHookInstaller.hookCommand(for: managed.path)
        let original = settings(["PermissionRequest": [managedCommand, vibeCommand, "node custom-user-hook.js"]])
        let settingsURL = directory.appendingPathComponent("settings.json")
        try original.write(to: settingsURL)
        let report = HookHealthCheck.checkClaude(claudeDirectory: directory, hooksBinaryURL: bundle, managedHooksBinaryURL: managed)
        let conflicts = report.issues.compactMap { issue -> [String]? in
            if case let .strayIslandHooksDetected(commands) = issue { return commands }
            return nil
        }.flatMap { $0 }
        #expect(conflicts == [vibeCommand])
        #expect(try Data(contentsOf: settingsURL) == original)
        try settings(["PermissionRequest": [managedCommand]]).write(to: settingsURL)
        let ownOnly = HookHealthCheck.checkClaude(claudeDirectory: directory, hooksBinaryURL: bundle, managedHooksBinaryURL: managed)
        #expect(!ownOnly.issues.contains { if case .strayIslandHooksDetected = $0 { return true }; return false })
    }

    /// Without a command to exclude, our own rows read as someone else's — the
    /// reason the health check skips this whole test when it cannot resolve the
    /// binary rather than accusing the island of squatting on itself.
    @Test
    func withoutAKnownCommandOurRowsWouldBeMisread() {
        let data = settings(["Stop": [ours]])
        #expect(ClaudeHookInstaller.strayIslandHookCommands(in: data, excluding: nil) == [ours])

        let report = HookHealthCheck.checkClaude(
            claudeDirectory: URL(fileURLWithPath: "/nonexistent-island-test"),
            hooksBinaryURL: nil,
            managedHooksBinaryURL: URL(fileURLWithPath: "/nonexistent-island-test/OpenIslandHooks")
        )
        #expect(report.issues.contains { if case .strayIslandHooksDetected = $0 { return true } else { return false } } == false)
    }
}
