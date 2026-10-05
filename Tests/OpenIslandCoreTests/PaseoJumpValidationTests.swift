import Testing
@testable import OpenIslandCore

private actor JumpStatusMock {
    var nativeID = "native"
    var status = "running"
    var unavailable = false
    var missing = false
    var duplicate = false
    var calls: [String] = []
    func change(nativeID: String = "native", status: String = "running", unavailable: Bool = false, missing: Bool = false, duplicate: Bool = false) {
        self.nativeID = nativeID; self.status = status; self.unavailable = unavailable
        self.missing = missing; self.duplicate = duplicate
    }
    func history() -> [String] { calls }
    func call(_ name: String, _ input: ClaudeHookJSONValue) -> ClaudeHookJSONValue {
        calls.append(name)
        if name == "list_agents" {
            return .object(["agents": .array((duplicate ? ["agent", "other"] : ["agent"]).map { .object(["id": .string($0)]) })])
        }
        if missing { return .object([:]) }
        var id = "agent"
        if case let .object(values) = input, case let .string(value)? = values["agentId"] { id = value }
        return .object(["snapshot": .object([
            "id": .string(id), "provider": .string("claude"), "status": .string(status),
            "providerUnavailable": .boolean(unavailable), "title": .string("Current title"),
            "persistence": .object(["provider": .string("claude"), "sessionId": .string(nativeID)])
        ])])
    }
}

@Suite @MainActor
struct PaseoJumpValidationTests {
    @Test func suppliedAndCachedIdentityUseFreshSingleStatusCall() async throws {
        let mock = JumpStatusMock()
        let coordinator = PaseoQuestionCoordinator(call: { name, input in await mock.call(name, input) })
        let first = try await coordinator.resolveBinding(sessionID: "native", agentID: "agent")
        #expect(first.title == "Current title")
        _ = try await coordinator.resolveBinding(sessionID: "native")
        #expect(await mock.history() == ["get_agent_status", "get_agent_status"])
        await mock.change(nativeID: "reassigned")
        await #expect(throws: PaseoQuestionError.self) { try await coordinator.resolveBinding(sessionID: "native") }
    }

    @Test func missingClosedAndUnavailableTargetsFail() async {
        let mock = JumpStatusMock()
        let coordinator = PaseoQuestionCoordinator(call: { name, input in await mock.call(name, input) })
        await mock.change(missing: true)
        await #expect(throws: PaseoQuestionError.self) { try await coordinator.resolveBinding(sessionID: "native", agentID: "agent") }
        await mock.change(status: "closed")
        await #expect(throws: PaseoQuestionError.self) { try await coordinator.resolveBinding(sessionID: "native", agentID: "agent") }
        await mock.change(unavailable: true)
        await #expect(throws: PaseoQuestionError.self) { try await coordinator.resolveBinding(sessionID: "native", agentID: "agent") }
    }

    @Test func unboundDiscoveryRejectsDuplicateNativeIdentityEvenWithHint() async {
        let mock = JumpStatusMock()
        await mock.change(duplicate: true)
        let coordinator = PaseoQuestionCoordinator(call: { name, input in await mock.call(name, input) })
        await #expect(throws: PaseoQuestionError.self) { try await coordinator.resolveBinding(sessionID: "native") }
        let count = await mock.history().count
        await #expect(throws: PaseoQuestionError.self) { try await coordinator.resolveBinding(sessionID: "native", agentID: "agent") }
        #expect(await mock.history().count == count)
    }
}
