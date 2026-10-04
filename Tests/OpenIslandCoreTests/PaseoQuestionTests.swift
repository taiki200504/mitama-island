import Foundation
import Testing
@testable import OpenIslandCore

private func paseoFixture(_ text: String) throws -> ClaudeHookJSONValue {
    try JSONDecoder().decode(ClaudeHookJSONValue.self, from: Data(text.utf8))
}

private let paseoSnapshot = """
{"id":"agent-1","provider":"claude","cwd":"/project","title":"Test Paseo","status":"running",
 "persistence":{"provider":"claude","sessionId":"native-session","nativeHandle":"native-session"},
 "pendingPermissions":[{"id":"request-1","name":"AskUserQuestion","kind":"tool","input":{
   "untouched":"preserved","annotations":{"old":{"notes":"keep"}},"questions":[
   {"question":"Which?","header":"Choice","multiSelect":true,"options":[{"label":"One","description":"First"},{"label":"Two"}]},
   {"question":"Why?","header":"Reason","options":[{"label":"Yes"}]}]}}]}
"""

private actor PaseoMock {
    var snapshot: ClaudeHookJSONValue
    var calls: [(String, ClaudeHookJSONValue)] = []
    var failAnswer = false
    var delayAnswer = false
    var omitSuccess = false
    init() throws { snapshot = try paseoFixture(paseoSnapshot) }
    func replace(_ text: String) throws { snapshot = try paseoFixture(text) }
    func setFailure(_ value: Bool) { failAnswer = value }
    func setDelay() { delayAnswer = true }
    func setOmittedSuccess() { omitSuccess = true }
    func call(_ name: String, _ input: ClaudeHookJSONValue) async throws -> ClaudeHookJSONValue {
        calls.append((name, input))
        switch name {
        case "list_pending_permissions":
            let data = try JSONEncoder().encode(snapshot)
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let pending = (object?["pendingPermissions"] as? [[String: Any]]) ?? []
            let requests = try pending.map { request -> ClaudeHookJSONValue in
                let json = try JSONSerialization.data(withJSONObject: request)
                let input = try JSONDecoder().decode(ClaudeHookJSONValue.self, from: json)
                return .object(["agentId": .string("agent-1"), "status": .string("running"), "request": input])
            }
            // Repeated entries and unrelated Bash permissions must not trigger extra status calls.
            return .object(["permissions": .array(requests + requests + [.object([
                "agentId": .string("unrelated-agent"), "request": .object(["name": .string("Bash")])
            ])])])
        case "get_agent_status": return .object(["snapshot": snapshot])
        case "respond_to_permission":
            if delayAnswer { try await Task.sleep(for: .milliseconds(80)) }
            if failAnswer { throw PaseoQuestionError.invalidResponse }
            return omitSuccess ? .object([:]) : .object(["success": .boolean(true)])
        default: throw PaseoQuestionError.invalidResponse
        }
    }
}

struct PaseoQuestionTests {
    @Test func decodesJSONAndSSEAndRejectsErrors() throws {
        let json = #"{"jsonrpc":"2.0","id":"123","result":{"structuredContent":{"agents":[]}}}"#
        let expected = try paseoFixture(#"{"agents":[]}"#)
        #expect(try PaseoMCPClient.decode(Data(json.utf8), id: "123") == expected)
        let sse = "event: message\ndata: {\"method\":\"notifications/progress\"}\n\nevent: message\ndata: \(json)\n\n"
        #expect(try PaseoMCPClient.decode(Data(sse.utf8), id: "123") == expected)
        let textResult = #"{"id":"123","result":{"content":[{"type":"text","text":"{\"agents\":[]}"}]}}"#
        #expect(try PaseoMCPClient.decode(Data(textResult.utf8), id: "123") == expected)
        #expect(throws: PaseoQuestionError.self) {
            try PaseoMCPClient.decode(Data(#"{"id":"123","result":{"isError":true}}"#.utf8), id: "123")
        }
        #expect(throws: PaseoQuestionError.self) { try PaseoMCPClient.decode(Data(json.utf8), id: "wrong") }
    }

    @Test @MainActor func discoversAndAnswersPreservingOriginalInput() async throws {
        let mock = try PaseoMock()
        let coordinator = PaseoQuestionCoordinator(call: { try await mock.call($0, $1) })
        await coordinator.poll()
        let question = try #require(coordinator.questions["native-session"])
        #expect(question.agentID == "agent-1")
        #expect(question.prompt.questions.count == 2)
        #expect(question.prompt.questions[0].multiSelect)
        #expect(question.prompt.questions[0].options.last?.allowsFreeform == true)
        await coordinator.poll()
        #expect(coordinator.questions["native-session"]?.prompt.id == question.prompt.id)
        try await coordinator.answer(sessionID: "native-session", promptID: question.prompt.id, response: .init(
            answers: ["Which?": "One, Two", "Why?": "My own reason"], annotations: ["Why?": .init(notes: "note")]
        ))
        let calls = await mock.calls
        let answer = try #require(calls.last)
        #expect(answer.0 == "respond_to_permission")
        let encoded = try JSONEncoder().encode(answer.1)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["agentId"] as? String == "agent-1")
        #expect(object["requestId"] as? String == "request-1")
        let response = try #require(object["response"] as? [String: Any])
        #expect(response["behavior"] as? String == "allow")
        let input = try #require(response["updatedInput"] as? [String: Any])
        #expect(input["untouched"] as? String == "preserved")
        #expect((input["answers"] as? [String: String]) == ["Which?": "One, Two", "Why?": "My own reason"])
        #expect((input["questions"] as? [Any])?.count == 2)
        #expect((input["annotations"] as? [String: Any])?.count == 2)
        #expect(coordinator.questions.isEmpty)
    }

    @Test @MainActor func failureLeavesQuestionForRetryAndExpiredRequestIsNotSent() async throws {
        let mock = try PaseoMock()
        let coordinator = PaseoQuestionCoordinator(call: { try await mock.call($0, $1) })
        await coordinator.poll()
        let question = try #require(coordinator.questions["native-session"])
        await mock.setFailure(true)
        do {
            try await coordinator.answer(sessionID: question.sessionID, promptID: question.prompt.id, response: .init(answers: ["Which?": "One", "Why?": "Yes"]))
            Issue.record("A failed send must throw")
        } catch {}
        #expect(coordinator.questions[question.sessionID] == question)
        await mock.setFailure(false)
        try await coordinator.answer(sessionID: question.sessionID, promptID: question.prompt.id, response: .init(answers: ["Which?": "One", "Why?": "Yes"]))
        #expect(coordinator.questions.isEmpty)
        await coordinator.poll()
        let next = try #require(coordinator.questions["native-session"])
        try await mock.replace(paseoSnapshot.replacingOccurrences(of: "request-1", with: "request-2"))
        let before = await mock.calls.count
        do {
            try await coordinator.answer(sessionID: next.sessionID, promptID: next.prompt.id, response: .init(answers: ["Which?": "One", "Why?": "Yes"]))
            Issue.record("An expired request must throw")
        } catch {}
        let after = await mock.calls
        #expect(after.count == before + 1)
        #expect(after.last?.0 == "get_agent_status")
        await coordinator.poll()
        #expect(coordinator.questions[next.sessionID]?.requestID == "request-2")
        try await mock.replace(paseoSnapshot.replacingOccurrences(of: "AskUserQuestion", with: "Bash"))
        await coordinator.poll()
        #expect(coordinator.questions.isEmpty)
    }

    @Test @MainActor func fetchesOnlyUniqueQuestionAgentStatusesAndDoesNotMatchByCwd() async throws {
        let mock = try PaseoMock()
        let coordinator = PaseoQuestionCoordinator(call: { try await mock.call($0, $1) })
        await coordinator.poll()
        #expect(coordinator.questions["native-session"]?.agentID == "agent-1")
        #expect(await mock.calls.map(\.0) == ["list_pending_permissions", "get_agent_status"])
        try await mock.replace(paseoSnapshot.replacingOccurrences(of: #","sessionId":"native-session","nativeHandle":"native-session""#, with: ""))
        await coordinator.poll()
        #expect(coordinator.questions.isEmpty)
    }

    @Test @MainActor func missingSuccessDoesNotClearQuestion() async throws {
        let mock = try PaseoMock()
        await mock.setOmittedSuccess()
        let coordinator = PaseoQuestionCoordinator(call: { try await mock.call($0, $1) })
        await coordinator.poll()
        let question = try #require(coordinator.questions["native-session"])
        do {
            try await coordinator.answer(sessionID: question.sessionID, promptID: question.prompt.id,
                                         response: .init(answers: ["Which?": "One", "Why?": "Yes"]))
            Issue.record("Missing success acknowledgement must fail")
        } catch {}
        #expect(coordinator.questions[question.sessionID] == question)
    }

    @Test @MainActor func preventsDuplicateSubmission() async throws {
        let mock = try PaseoMock()
        await mock.setDelay()
        let coordinator = PaseoQuestionCoordinator(call: { try await mock.call($0, $1) })
        await coordinator.poll()
        let question = try #require(coordinator.questions["native-session"])
        let first = Task { try await coordinator.answer(sessionID: question.sessionID, promptID: question.prompt.id, response: .init(answers: ["Which?": "One", "Why?": "Yes"])) }
        for _ in 0..<100 {
            if await mock.calls.contains(where: { $0.0 == "respond_to_permission" }) { break }
            await Task.yield()
        }
        #expect(await mock.calls.contains(where: { $0.0 == "respond_to_permission" }))
        do {
            try await coordinator.answer(sessionID: question.sessionID, promptID: question.prompt.id, response: .init(answers: ["Which?": "Two", "Why?": "Yes"]))
            Issue.record("Duplicate send must throw")
        } catch {}
        try await first.value
        let responses = await mock.calls.filter { $0.0 == "respond_to_permission" }
        #expect(responses.count == 1)
    }
}
