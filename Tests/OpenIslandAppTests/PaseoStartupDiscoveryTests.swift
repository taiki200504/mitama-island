import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

/// An idle Paseo conversation fires no hook, so after a relaunch the island only
/// learns about it from Claude Code's process registry plus Paseo's agent list.
@MainActor struct PaseoStartupDiscoveryTests {
    nonisolated private static func call(_ name: String, _ input: ClaudeHookJSONValue) -> ClaudeHookJSONValue {
        if name == "list_agents" {
            return .object(["agents": .array(["idle", "codex-agent"].map { .object(["id": .string($0)]) })])
        }
        guard case let .object(args) = input, case let .string(id)? = args["agentId"] else { return .null }
        return .object(["snapshot": .object([
            "id": .string(id), "provider": .string(id == "idle" ? "claude" : "codex"),
            "title": .string(id == "idle" ? "施策の日常化" : "codex"), "cwd": .string("/project"),
            "status": .string("idle"), "pendingPermissions": .array([]),
            "persistence": .object(["sessionId": .string(id + "-native")]),
        ])])
    }

    @Test func idleConversationMissingFromTheIslandIsAdded() async {
        let coordinator = PaseoQuestionCoordinator(call: { Self.call($0, $1) })
        let model = isolatedPaseoAppModel(coordinator)

        await model.reconcilePaseoSessionsOnce(liveClaudeSessionIDs: ["idle-native", "codex-agent-native", "terminal-only"])

        let session = model.state.session(id: "idle-native")
        #expect(session?.title == "施策の日常化")
        #expect(session?.jumpTarget?.terminalApp == "Paseo")
        #expect(session?.jumpTarget?.paseoAgentID == "idle")
        #expect(session?.phase == .completed)
        #expect(model.state.session(id: "codex-agent-native") == nil)
        #expect(model.state.session(id: "terminal-only") == nil)
    }
}
