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
