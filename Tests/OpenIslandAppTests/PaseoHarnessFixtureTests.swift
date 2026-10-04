import Testing
@testable import OpenIslandApp
import OpenIslandCore

@Suite struct PaseoHarnessFixtureTests {
    @Test func childStatusUsesRequestedIdentityAndRejectsUnknownAgent() async throws {
        let fixture = PaseoHarnessFixture(isQuestion: true, variant: .child)
        let parent = try await fixture.call("get_agent_status", .object(["agentId": .string("fixture-parent")]))
        let child = try await fixture.call("get_agent_status", .object(["agentId": .string("fixture-child")]))
        guard case let .object(parentResult) = parent, case let .object(parentSnapshot)? = parentResult["snapshot"],
              case let .object(childResult) = child, case let .object(childSnapshot)? = childResult["snapshot"] else {
            Issue.record("Expected exact snapshots"); return
        }
        #expect(parentSnapshot["id"] == .string("fixture-parent"))
        #expect(parentSnapshot["pendingPermissions"] == .array([]))
        #expect(childSnapshot["id"] == .string("fixture-child"))
        #expect(childSnapshot["labels"] == .object(["paseo.parent-agent-id": .string("fixture-parent")]))
        await #expect(throws: PaseoQuestionError.self) {
            try await fixture.call("get_agent_status", .object(["agentId": .string("real-agent")]))
        }
        await #expect(throws: PaseoQuestionError.self) {
            try await fixture.call("respond_to_permission", .object(["agentId": .string("real-agent"), "requestId": .string("fixture-request")]))
        }
    }
}
