import Foundation
import Testing
@testable import OpenIslandCore

struct PaseoDelegationTests {
    private static func value(_ text: String) throws -> ClaudeHookJSONValue {
        try JSONDecoder().decode(ClaudeHookJSONValue.self, from: Data(text.utf8))
    }

    @MainActor private func coordinator(parent: String?, parentSnapshot: String?) throws -> PaseoQuestionCoordinator {
        let label = parent.map { #", "labels":{"paseo.parent-agent-id":"\#($0)"}"# } ?? ""
        let snapshot = try Self.value("""
        {"id":"child","provider":"claude","status":"running","persistence":{"provider":"claude","sessionId":"native-child"}\(label),
        "pendingPermissions":[{"id":"request","name":"AskUserQuestion","kind":"tool","input":{"questions":[{"question":"Which?","options":[{"label":"Yes"}]}]}}]}
        """)
        let parentValue = try parentSnapshot.map(Self.value)
        return PaseoQuestionCoordinator(call: { name, arguments in
            switch name {
            case "list_pending_permissions":
                return .object(["permissions": .array([.object(["agentId": .string("child"), "request": .object(["id": .string("request")])])])])
            case "get_agent_status":
                if case let .object(values) = arguments, values["agentId"] == .string("child") { return .object(["snapshot": snapshot]) }
                if let parentValue { return .object(["snapshot": parentValue]) }
                throw PaseoQuestionError.invalidResponse
            default: throw PaseoQuestionError.invalidResponse
            }
        }, providerAliases: [:])
    }

    @Test @MainActor func parentWithoutNativeIdentityRequiresVisibleHandoff() async throws {
        let coordinator = try coordinator(parent: " parent ", parentSnapshot: #"{"id":"parent","status":"running","archivedAt":null}"#)
        await coordinator.poll()
        #expect(coordinator.delegatedSessionIDs.isEmpty)
        #expect(coordinator.parentSessionID(for: "native-child") == nil)
        #expect(coordinator.questions["native-child"] != nil)
        #expect(coordinator.needsParentHandoff(sessionID: "native-child"))
    }

    @Test @MainActor func mainQuestionRemainsVisible() async throws {
        let coordinator = try coordinator(parent: nil, parentSnapshot: nil)
        await coordinator.poll()
        #expect(coordinator.delegatedSessionIDs.isEmpty)
        #expect(coordinator.questions["native-child"] != nil)
        #expect(!coordinator.needsParentHandoff(sessionID: "native-child"))
    }

    @Test @MainActor func orphanAndUnavailableParentsRemainVisible() async throws {
        for parent in [nil, #"{"id":"parent","status":"closed"}"#, #"{"id":"parent","status":"idle","archivedAt":"2026-10-05"}"#, #"{"id":"parent","status":"error"}"#, #"{"id":"parent","status":"running","providerUnavailable":true}"#] {
            let coordinator = try coordinator(parent: "parent", parentSnapshot: parent)
            await coordinator.poll()
            #expect(coordinator.delegatedSessionIDs.isEmpty)
            #expect(coordinator.questions["native-child"] != nil)
            #expect(coordinator.needsParentHandoff(sessionID: "native-child"))
        }
    }
}
