import Foundation
import Testing
@testable import OpenIslandCore

private actor ConnectionReply {
    enum Failure: Error { case offline }
    var result: ClaudeHookJSONValue = .object(["permissions": .array([])])
    var fails = false
    var continuation: CheckedContinuation<ClaudeHookJSONValue, Never>?
    var delay = false
    func configure(result: ClaudeHookJSONValue, fails: Bool = false) {
        self.result = result
        self.fails = fails
    }
    func suspendNext() { delay = true }
    func isWaiting() -> Bool { continuation != nil }
    func resume() { continuation?.resume(returning: result); continuation = nil }
    func call() async throws -> ClaudeHookJSONValue {
        if fails { throw Failure.offline }
        if delay {
            delay = false
            return await withCheckedContinuation { continuation = $0 }
        }
        return result
    }
}

@Suite @MainActor
struct PaseoConnectionTests {
    @Test func emptySuccessfulArrayIsConnectedAndObserved() async {
        let reply = ConnectionReply()
        let coordinator = PaseoQuestionCoordinator(call: { _, _ in try await reply.call() })
        var changes: [PaseoConnectionState] = []
        coordinator.onHealthChange = { changes.append($0) }
        await coordinator.poll()
        #expect(coordinator.healthState == .connected)
        #expect(coordinator.requests.isEmpty)
        #expect(changes == [.connected])
        await coordinator.poll()
        #expect(changes == [.connected])
    }

    @Test func invalidResponseAndTransportFailureAreUnavailableThenRecover() async {
        let reply = ConnectionReply()
        let coordinator = PaseoQuestionCoordinator(call: { _, _ in try await reply.call() })
        await reply.configure(result: .object(["permissions": .string("invalid")]))
        await coordinator.poll()
        #expect(coordinator.healthState == .unavailable)
        await reply.configure(result: .object(["permissions": .array([])]), fails: true)
        await coordinator.poll()
        #expect(coordinator.healthState == .unavailable)
        await reply.configure(result: .object(["permissions": .array([])]))
        await coordinator.poll()
        #expect(coordinator.healthState == .connected)
        coordinator.stop()
        #expect(coordinator.healthState == .stopped)
        await coordinator.poll()
        #expect(coordinator.healthState == .connected)
    }

    @Test func transportFailureRetainsQuestionWhileConnectionBecomesUnavailable() async throws {
        let snapshot = try JSONDecoder().decode(ClaudeHookJSONValue.self, from: Data("""
        {"snapshot":{"id":"agent","provider":"claude","cwd":"/project","title":"Question","status":"running",
        "persistence":{"provider":"claude","sessionId":"native","nativeHandle":"native"},
        "pendingPermissions":[{"id":"request","name":"AskUserQuestion","kind":"tool","input":{
        "questions":[{"question":"Which?","options":[{"label":"Yes"}]}]}}]}}
        """.utf8))
        let reply = ConnectionReply()
        await reply.configure(result: .object(["permissions": .array([
            .object(["agentId": .string("agent"), "request": .object(["id": .string("request")])])
        ])]))
        let coordinator = PaseoQuestionCoordinator(call: { name, _ in
            if name == "get_agent_status" { return snapshot }
            return try await reply.call()
        })
        await coordinator.poll()
        #expect(coordinator.questions.count == 1)
        let retained = coordinator.requests
        await reply.configure(result: .null, fails: true)
        await coordinator.poll()
        #expect(coordinator.healthState == .unavailable)
        #expect(coordinator.requests == retained)
    }

    @Test func responseAfterStopCannotReconnect() async {
        let reply = ConnectionReply()
        await reply.suspendNext()
        let coordinator = PaseoQuestionCoordinator(call: { _, _ in try await reply.call() })
        let pending = Task { await coordinator.poll() }
        while !(await reply.isWaiting()) { await Task.yield() }
        coordinator.stop()
        await reply.resume()
        await pending.value
        #expect(coordinator.healthState == .stopped)
        #expect(coordinator.requests.isEmpty)
    }
}
