import Foundation
import Testing
@testable import OpenIslandCore

struct BridgeAnswerDeliveryTests {
    @Test func missingWaiterRejectsBothAnswers() throws {
        let socket = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socket)
        try server.start()
        defer { server.stop() }
        let client = BridgeCommandClient(socketURL: socket)
        #expect(try client.send(.resolvePermission(sessionID: "missing", resolution: .allowOnce())) == .rejected)
        #expect(try client.send(.answerQuestion(sessionID: "missing", response: QuestionPromptResponse(answer: "fixture"))) == .rejected)
        let data = try BridgeCodec.encodeLine(.response(.rejected))
        var buffer = data
        #expect(try BridgeCodec.decodeLines(from: &buffer) == [.response(.rejected)])
    }
}

extension BridgeAnswerDeliveryTests {
    @Test func liveWaiterRejectsStaleIDThenAcceptsCurrentID() async throws {
        let socket = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socket)
        try server.start()
        defer { server.stop() }
        let observer = LocalBridgeClient(socketURL: socket)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))
        let payload = ClaudeHookPayload(cwd: "/tmp/fixture", hookEventName: .permissionRequest,
            sessionID: "live", toolName: "Bash", toolInput: .object(["command": .string("fixture only")]), toolUseID: "fixture-tool")
        let waiting = Task.detached { try BridgeCommandClient(socketURL: socket).send(.processClaudeHook(payload), timeout: 5) }
        var iterator = stream.makeAsyncIterator()
        var requestID: UUID?
        while let event = try await iterator.next() {
            if case let .permissionRequested(value) = event { requestID = value.request.id; break }
        }
        let id = try #require(requestID)
        let client = BridgeCommandClient(socketURL: socket)
        let stale = BridgeCommand.resolvePermission(sessionID: "live", resolution: .allowOnce(), expectedRequestID: UUID())
        let encoded = try JSONEncoder().encode(stale)
        #expect(try JSONDecoder().decode(BridgeCommand.self, from: encoded) == stale)
        #expect(try client.send(stale) == .rejected)
        #expect(server.hasLivePendingHook(sessionID: "live"))
        #expect(try client.send(.resolvePermission(sessionID: "live", resolution: .allowOnce(), expectedRequestID: id)) == .acknowledged)
        guard case .claudeHookDirective(.permissionRequest(.allow))? = try await waiting.value else {
            Issue.record("Live hook did not receive approval")
            return
        }
        #expect(!server.hasLivePendingHook(sessionID: "live"))
        #expect(try client.send(.resolvePermission(sessionID: "live", resolution: .allowOnce(), expectedRequestID: id)) == .rejected)
    }
}

extension BridgeAnswerDeliveryTests {
    @Test func paseoResolvedRequestReleasesItsLiveHook() async throws {
        let socket = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socket)
        try server.start()
        defer { server.stop() }
        let observer = LocalBridgeClient(socketURL: socket)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))
        let input: ClaudeHookJSONValue = .object(["questions": .array([.object(["question": .string("Choose")])])])
        let payload = ClaudeHookPayload(cwd: "/tmp/fixture", hookEventName: .permissionRequest,
            sessionID: "paseo-live", toolName: "AskUserQuestion", toolInput: input, toolUseID: "tool-1")
        let waiting = Task.detached { try BridgeCommandClient(socketURL: socket).send(.processClaudeHook(payload), timeout: 5) }
        var iterator = stream.makeAsyncIterator()
        while let event = try await iterator.next() {
            if case .questionAsked = event { break }
            if case .permissionRequested = event { break }
        }
        #expect(server.hasLivePendingHook(sessionID: "paseo-live"))
        let binding = PaseoAgentBinding(agentID: "agent", sessionID: "paseo-live", provider: "claude",
            hostProvider: "claude", title: "t", cwd: "/tmp/fixture")
        func pending(_ toolUseID: String) -> PaseoPendingRequest {
            PaseoPendingRequest(binding: binding, requestID: "r", name: "AskUserQuestion", kind: "question",
                input: .object(["questions": .array([]), "allowOther": .boolean(true)]), toolUseID: toolUseID,
                originalRequest: .object([:]))
        }
        #expect(!server.releaseMatchingPaseoHook(pending("other-tool")))
        #expect(server.hasLivePendingHook(sessionID: "paseo-live"))
        #expect(server.releaseMatchingPaseoHook(pending("tool-1")))
        _ = try await waiting.value
        #expect(!server.hasLivePendingHook(sessionID: "paseo-live"))
    }
}
