import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
struct PaseoDelegationWiringTests {
    @Test func confirmedChildDoesNotBecomeFocusedOrSelectedOrRemainAnActiveCard() async throws {
        let snapshot: ClaudeHookJSONValue = .object([
            "id": .string("child"), "provider": .string("claude"), "status": .string("running"),
            "title": .string("Child"), "persistence": .object(["sessionId": .string("native-child")]),
            "labels": .object(["paseo.parent-agent-id": .string("parent")]),
            "pendingPermissions": .array([.object([
                "id": .string("q"), "name": .string("AskUserQuestion"), "kind": .string("tool"),
                "input": .object(["questions": .array([.object([
                    "question": .string("Which?"), "options": .array([.object(["label": .string("Yes")])])
                ])])])
            ])])
        ])
        let coordinator = PaseoQuestionCoordinator(call: { name, input in
            if name == "list_pending_permissions" {
                return .object(["permissions": .array([.object(["agentId": .string("child"), "request": .object(["id": .string("q")])])])])
            }
            if name == "get_agent_status", case let .object(values) = input {
                if values["agentId"] == .string("child") { return .object(["snapshot": snapshot]) }
                return .object(["snapshot": .object(["id": .string("parent"), "status": .string("idle")])])
            }
            throw PaseoQuestionError.invalidResponse
        }, providerAliases: [:])
        let model = AppModel(paseoQuestions: coordinator)
        model.state = SessionState(sessions: [
            AgentSession(id: "native-child", title: "Old child", tool: .claudeCode, origin: .live, attachmentState: .attached, phase: .waitingForAnswer,
                         summary: "Child", updatedAt: .now, jumpTarget: JumpTarget(terminalApp: "Paseo", workspaceName: "", paneTitle: "")),
            AgentSession(id: "main", title: "Main", tool: .claudeCode, origin: .live, attachmentState: .attached, phase: .waitingForAnswer,
                         summary: "Main", updatedAt: .now.addingTimeInterval(-1))
        ])
        model.selectedSessionID = "native-child"
        model.connectPaseoQuestions()
        coordinator.stop()
        await coordinator.poll()
        #expect(model.selectedSessionID == "main")
        #expect(model.focusedSession?.id == "main")
        #expect(model.liveAttentionCount == 1)
        model.islandSurface = .sessionList(actionableSessionID: "native-child")
        #expect(model.activeIslandCardSession == nil)
        #expect(!model.islandSurfaceAwaitsUserAction)
    }
}
