import Foundation
import Testing
@testable import OpenIslandCore

private func json(_ text: String) throws -> ClaudeHookJSONValue {
    try JSONDecoder().decode(ClaudeHookJSONValue.self, from: Data(text.utf8))
}
private actor NativePaseoMock {
    var snapshot: ClaudeHookJSONValue
    var fail = false
    var delay = false
    var calls: [(String, ClaudeHookJSONValue)] = []
    init(provider: String = "claude", request: String = "", mode: String = "bypassPermissions") throws {
        let toolRequest = request.isEmpty ? #"{"id":"request","provider":"claude","name":"Bash","kind":"tool","input":{"command":"echo example","untouched":"keep"},"metadata":{"toolUseId":"tool-1"},"suggestions":[{"type":"addRules","destination":"session","rules":[{"toolName":"Bash","ruleContent":"echo example"}],"behavior":"allow"}]}"# : request
        snapshot = try json("""
        {"id":"agent","provider":"\(provider)","status":"running","title":"Sample","cwd":"/same-project",
         "currentModeId":"\(mode)","availableModes":[{"id":"\(mode)","label":"Current mode"}],
         "persistence":{"provider":"\(provider)","sessionId":"native","nativeHandle":"native"},"pendingPermissions":[\(toolRequest)]}
        """)
    }
    func setFailure(_ value: Bool) { fail = value }
    func setDelay() { delay = true }
    func replace(_ old: String, _ new: String) throws {
        let encoded = try JSONEncoder().encode(snapshot)
        snapshot = try json(String(decoding: encoded, as: UTF8.self).replacingOccurrences(of: old, with: new))
    }
    func call(_ name: String, _ input: ClaudeHookJSONValue) async throws -> ClaudeHookJSONValue {
        calls.append((name, input))
        if name == "list_agents" { return .object(["agents": .array([.object(["id": .string("agent")])])]) }
        if name == "get_agent_status" { return .object(["snapshot": snapshot]) }
        if name == "list_pending_permissions" {
            return .object(["permissions": .array([.object(["agentId": .string("agent"), "request": .object(["id": .string("request")])])])])
        }
        if delay { try await Task.sleep(for: .milliseconds(100)) }
        if fail { throw PaseoQuestionError.invalidResponse }
        return .object(["success": .boolean(true)])
    }
}
private func arguments(_ value: ClaudeHookJSONValue) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
}

@MainActor
struct PaseoPermissionTests {
    @Test func autoAliasUsesNativeClaudeAndRepeatedPollDoesNotNotifyAgain() async throws {
        let mock = try NativePaseoMock(provider: "auto")
        let coordinator = PaseoQuestionCoordinator(call: { try await mock.call($0, $1) }, providerAliases: ["auto": "claude"])
        var changes = 0
        coordinator.onRequestsChange = { _, _ in changes += 1 }
        await coordinator.poll()
        let first = try #require(coordinator.requests["native"])
        #expect(first.binding.provider == "claude")
        #expect(first.binding.hostProvider == "auto")
        #expect(first.permission?.suggestedUpdates.count == 1)
        await coordinator.poll()
        #expect(coordinator.requests["native"]?.permission?.id == first.permission?.id)
        #expect(changes == 1)
        _ = try await coordinator.approve(sessionID: "native", requestID: "request", action: .allowOnce)
        let call = try #require(await mock.calls.last)
        let root = try arguments(call.1)
        let response = try #require(root["response"] as? [String: Any])
        #expect(response["behavior"] as? String == "allow")
        #expect(response["updatedPermissions"] == nil)
        #expect(response["selectedActionId"] == nil)
        #expect((response["updatedInput"] as? [String: String])?["untouched"] == "keep")
        #expect(root["agentId"] as? String == "agent")
    }

    @Test func onlyOfferedClaudeSuggestionsAreAllowed() async throws {
        let mock = try NativePaseoMock()
        let coordinator = PaseoQuestionCoordinator(call: { try await mock.call($0, $1) })
        await coordinator.poll()
        let suggestion = try #require(coordinator.requests["native"]?.permission?.suggestedUpdates.first)
        do {
            _ = try await coordinator.approve(sessionID: "native", requestID: "request", action: .allowWithUpdates([.setMode(destination: .session, mode: .bypassPermissions)]))
            Issue.record("An invented mode suggestion must be rejected")
        } catch {}
        #expect(await mock.calls.filter { $0.0 == "respond_to_permission" }.isEmpty)
        _ = try await coordinator.approve(sessionID: "native", requestID: "request", action: .allowWithUpdates([suggestion]))
        let responseCall = try #require(await mock.calls.last)
        let responseArguments = try arguments(responseCall.1)
        let response = try #require(responseArguments["response"] as? [String: Any])
        #expect((response["updatedPermissions"] as? [Any])?.count == 1)
    }

    @Test func codexToolHasNoFakeStandingPermissions() async throws {
        let request = #"{"id":"request","provider":"codex","name":"commandExecution","kind":"tool","input":{"command":"echo example"},"suggestions":[{"type":"setMode","destination":"session","mode":"bypassPermissions"}]}"#
        let mock = try NativePaseoMock(provider: "codex", request: request, mode: "full-access")
        let coordinator = PaseoQuestionCoordinator(call: { try await mock.call($0, $1) })
        await coordinator.poll()
        #expect(coordinator.requests["native"]?.permission?.suggestedUpdates.isEmpty == true)
        do {
            _ = try await coordinator.approve(sessionID: "native", requestID: "request", action: .allowWithUpdates([.setMode(destination: .session, mode: .bypassPermissions)]))
            Issue.record("Codex cannot accept standing permission updates")
        } catch {}
        _ = try await coordinator.approve(sessionID: "native", requestID: "request", action: .deny)
        let responseCall = try #require(await mock.calls.last)
        let responseArguments = try arguments(responseCall.1)
        let response = try #require(responseArguments["response"] as? [String: Any])
        #expect(response["behavior"] as? String == "deny")
        #expect(response["updatedPermissions"] == nil)
        #expect(await mock.calls.contains { $0.0 == "set_agent_mode" } == false)
    }

    @Test func planYesResumesOnlyProviderOfferedPriorBypass() async throws {
        let request = #"{"id":"request","provider":"claude","name":"ExitPlanMode","kind":"plan","input":{"plan":"example"},"actions":[{"id":"reject","label":"Reject","behavior":"deny","variant":"danger","intent":"dismiss"},{"id":"implement","label":"Implement","behavior":"allow","variant":"primary","intent":"implement"},{"id":"implement_resume","label":"Implement with Bypass permissions","behavior":"allow","variant":"secondary","intent":"implement_resume"}]}"#
        let mock = try NativePaseoMock(request: request, mode: "plan")
        let coordinator = PaseoQuestionCoordinator(call: { try await mock.call($0, $1) })
        await coordinator.poll()
        _ = try await coordinator.approve(sessionID: "native", requestID: "request", action: .allowOnce)
        let responseCall = try #require(await mock.calls.last)
        let responseArguments = try arguments(responseCall.1)
        let response = try #require(responseArguments["response"] as? [String: Any])
        #expect(response["selectedActionId"] as? String == "implement_resume")
        #expect(await mock.calls.contains { $0.0 == "set_agent_mode" } == false)
        await coordinator.poll()
        _ = try await coordinator.approve(sessionID: "native", requestID: "request", action: .paseoAction(requestID: "request", actionID: "implement"))
        let explicitCall = try #require(await mock.calls.last)
        let explicitArguments = try arguments(explicitCall.1)
        let explicit = try #require(explicitArguments["response"] as? [String: Any])
        #expect(explicit["selectedActionId"] as? String == "implement")
    }

    @Test func failureRetriesButExpiredIdentityCannotSubmit() async throws {
        let mock = try NativePaseoMock()
        let coordinator = PaseoQuestionCoordinator(call: { try await mock.call($0, $1) })
        await coordinator.poll()
        await mock.setFailure(true)
        do { _ = try await coordinator.approve(sessionID: "native", requestID: "request", action: .allowOnce); Issue.record("Expected failure") } catch {}
        #expect(coordinator.requests["native"] != nil)
        await mock.setFailure(false)
        _ = try await coordinator.approve(sessionID: "native", requestID: "request", action: .allowOnce)
        await coordinator.poll()
        try await mock.replace("request", "new-request")
        let before = await mock.calls.filter { $0.0 == "respond_to_permission" }.count
        do { _ = try await coordinator.approve(sessionID: "native", requestID: "request", action: .allowOnce); Issue.record("Expected expiration") } catch {}
        #expect(await mock.calls.filter { $0.0 == "respond_to_permission" }.count == before)
    }

    @Test func duplicatePermissionSubmissionSendsOnlyOnce() async throws {
        let mock = try NativePaseoMock()
        await mock.setDelay()
        let coordinator = PaseoQuestionCoordinator(call: { try await mock.call($0, $1) })
        await coordinator.poll()
        let first = Task { try await coordinator.approve(sessionID: "native", requestID: "request", action: .allowOnce) }
        for _ in 0..<100 {
            if await mock.calls.contains(where: { $0.0 == "respond_to_permission" }) { break }
            await Task.yield()
        }
        do {
            _ = try await coordinator.approve(sessionID: "native", requestID: "request", action: .allowOnce)
            Issue.record("Duplicate permission response must fail")
        } catch {}
        _ = try await first.value
        #expect(await mock.calls.filter { $0.0 == "respond_to_permission" }.count == 1)
    }

    @Test func runningCodexAsyncQuestionUsesHeaderKeysAndFreeText() async throws {
        let request = #"{"id":"request","provider":"codex","name":"request_user_input_async","kind":"question","input":{"untouched":"keep","questions":[{"id":"0","header":"Question 1","question":"Same text","options":[{"label":"One"}]},{"id":"1","header":"Question 2","question":"Same text","options":[]}]}}"#
        let mock = try NativePaseoMock(provider: "codex", request: request, mode: "full-access")
        let coordinator = PaseoQuestionCoordinator(call: { try await mock.call($0, $1) })
        await coordinator.poll()
        let question = try #require(coordinator.questions["native"])
        #expect(question.prompt.questions.map(\.responseKey) == ["Question 1", "Question 2"])
        #expect(question.prompt.questions[1].options.first?.allowsFreeform == true)
        try await coordinator.answer(sessionID: "native", promptID: question.prompt.id, response: .init(answers: ["Question 1": "One", "Question 2": "Typed explanation"]))
        let responseCall = try #require(await mock.calls.last)
        let responseArguments = try arguments(responseCall.1)
        let response = try #require(responseArguments["response"] as? [String: Any])
        let input = try #require(response["updatedInput"] as? [String: Any])
        #expect(input["answers"] as? [String: String] == ["Question 1": "One", "Question 2": "Typed explanation"])
        #expect(input["untouched"] as? String == "keep")
    }

    @Test func mismatchedNativeProviderAndUnknownKindDoNotBlindlyAllow() async throws {
        let request = #"{"id":"request","provider":"claude","name":"Unsupported","kind":"unknown","input":{}}"#
        let mock = try NativePaseoMock(request: request)
        let coordinator = PaseoQuestionCoordinator(call: { try await mock.call($0, $1) })
        await coordinator.poll()
        #expect(coordinator.requests["native"]?.permission?.requiresTerminalApproval == true)
        do { _ = try await coordinator.approve(sessionID: "native", requestID: "request", action: .allowOnce); Issue.record("Unknown kind cannot be accepted blindly") } catch {}
        #expect(await mock.calls.filter { $0.0 == "respond_to_permission" }.isEmpty)
        let mismatch = try NativePaseoMock(provider: "codex", request: request)
        let mismatched = PaseoQuestionCoordinator(call: { try await mismatch.call($0, $1) })
        await mismatched.poll()
        #expect(mismatched.requests.isEmpty)
    }
}
