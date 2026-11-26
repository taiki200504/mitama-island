import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

private actor FollowthroughMock {
    var pending = true
    var requestID = "question-request"
    func call(_ name: String, _ input: ClaudeHookJSONValue) throws -> ClaudeHookJSONValue {
        let snapshot: ClaudeHookJSONValue = .object([
            "id": .string("paseo-agent"), "provider": .string("claude"), "cwd": .string("/project"),
            "title": .string("Followthrough"), "status": .string("running"),
            "persistence": .object(["sessionId": .string("native")]),
            "pendingPermissions": .array(pending ? [.object([
                "id": .string(requestID), "name": .string("AskUserQuestion"),
                "input": .object(["questions": .array([.object([
                    "question": .string("Choose"), "header": .string("Choice"),
                    "options": .array([.object(["label": .string("One")])])
                ])])])
            ])] : [])
        ])
        if name == "list_pending_permissions" {
            return .object(["permissions": .array(pending ? [.object([
                "agentId": .string("paseo-agent"), "request": .object(["id": .string(requestID)])
            ])] : [])])
        }
        if name == "get_agent_status" { return .object(["snapshot": snapshot]) }
        pending = false
        return .object(["success": .boolean(true)])
    }

    func nextRequest() { requestID = "question-request-2"; pending = true }
}

@MainActor
struct PaseoAnswerFollowthroughTests {
    @Test func submitDoesNotClearCardUntilResumeEvent() async throws {
        let mock = FollowthroughMock()
        let coordinator = PaseoQuestionCoordinator(call: { try await mock.call($0, $1) })
        let model = isolatedPaseoAppModel(coordinator)
        model.connectPaseoQuestions()
        coordinator.stop()
        await coordinator.poll()
        let prompt = try #require(model.state.session(id: "native")?.questionPrompt)
        model.answerQuestion(for: "native", answer: .init(answers: ["Choose": "One"]), promptID: prompt.id)
        let deadline = ContinuousClock.now + .seconds(2)
        while model.paseoSendingSessionIDs.contains("native"), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.state.session(id: "native")?.questionPrompt?.id == prompt.id)
        #expect(model.paseoConfirmingResumeSessionIDs.contains("native"))
        model.applyTrackedEvent(.activityUpdated(SessionActivityUpdated(
            sessionID: "native", summary: "Working", phase: .running, timestamp: .now)))
        #expect(model.state.session(id: "native")?.questionPrompt == nil)
        #expect(!model.paseoConfirmingResumeSessionIDs.contains("native"))
    }

    @Test func newPendingRequestWhileConfirmingStillAppears() async throws {
        let mock = FollowthroughMock()
        let coordinator = PaseoQuestionCoordinator(call: { try await mock.call($0, $1) })
        let model = isolatedPaseoAppModel(coordinator)
        model.connectPaseoQuestions()
        coordinator.stop()
        await coordinator.poll()
        let first = try #require(model.state.session(id: "native")?.questionPrompt)
        model.answerQuestion(for: "native", answer: .init(answers: ["Choose": "One"]), promptID: first.id)
        let deadline = ContinuousClock.now + .seconds(2)
        while model.paseoSendingSessionIDs.contains("native"), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        await mock.nextRequest()
        await coordinator.poll()
        let next = try #require(model.state.session(id: "native")?.questionPrompt)
        #expect(next.id != first.id)
        #expect(model.paseoConfirmingResumeSessionIDs.contains("native"))
    }
}