import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

private actor FollowthroughMock {
    var pending = true
    var requestID = "question-request"
    var stallSubmit = false
    var failSubmit = false
    private var submitContinuations: [CheckedContinuation<Void, Never>] = []

    var isSubmitWaiting: Bool { !submitContinuations.isEmpty }

    func releaseSubmit() {
        stallSubmit = false
        submitContinuations.forEach { $0.resume() }
        submitContinuations.removeAll()
    }

    func call(_ name: String, _ input: ClaudeHookJSONValue) async throws -> ClaudeHookJSONValue {
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
        if stallSubmit {
            await withCheckedContinuation { submitContinuations.append($0) }
        }
        if failSubmit { throw PaseoQuestionError.invalidResponse }
        pending = false
        return .object(["success": .boolean(true)])
    }

    func nextRequest() { requestID = "question-request-2"; pending = true }
    func setStall(_ value: Bool) { stallSubmit = value }
    func setFail(_ value: Bool) { failSubmit = value }
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
        let deadline = ContinuousClock.now + .seconds(15)
        while model.paseoSendingSessionIDs.contains("native"), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(!model.paseoSendingSessionIDs.contains("native"))
        #expect(model.state.session(id: "native")?.questionPrompt?.id == prompt.id)
        try #require(model.paseoConfirmingResumeSessionIDs.contains("native"))
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
        let deadline = ContinuousClock.now + .seconds(15)
        while model.paseoSendingSessionIDs.contains("native"), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(!model.paseoSendingSessionIDs.contains("native"))
        await mock.nextRequest()
        await coordinator.poll()
        let next = try #require(model.state.session(id: "native")?.questionPrompt)
        #expect(next.id != first.id)
        #expect(!model.paseoConfirmingResumeSessionIDs.contains("native"))
    }

    @Test func unconfirmedQuestionCanOnlyBeAnsweredAgainOnANewPrompt() async throws {
        let mock = FollowthroughMock()
        let coordinator = PaseoQuestionCoordinator(call: { try await mock.call($0, $1) })
        let model = isolatedPaseoAppModel(coordinator)
        model.connectPaseoQuestions()
        coordinator.stop()
        await coordinator.poll()

        let answer = QuestionPromptResponse(answers: ["Choose": "One"])
        let first = try #require(model.state.session(id: "native")?.questionPrompt)
        model.answerQuestion(for: "native", answer: answer, promptID: first.id)
        let deadline = ContinuousClock.now + .seconds(15)
        while model.paseoSendingSessionIDs.contains("native"), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let submitted = try #require(model.paseoSubmittedAnswer(for: "native", promptID: first.id))
        model.expireUnconfirmedPaseoFollowthroughs(at: submitted.deadline)
        #expect(model.state.session(id: "native")?.questionPrompt?.id == first.id)
        #expect(model.remoteRelay.isCurrent?("native", first.id.uuidString) == false)
        #expect(model.remoteRelay.isWaiting?("native") == false)

        model.answerQuestion(for: "native", answer: answer)
        #expect(model.paseoSendingSessionIDs.isEmpty)
        #expect(model.paseoErrors["native"] == nil)

        await mock.nextRequest()
        await coordinator.poll()
        let next = try #require(model.state.session(id: "native")?.questionPrompt)
        #expect(next.id != first.id)
        #expect(model.remoteRelay.isCurrent?("native", next.id.uuidString) == true)
        model.answerQuestion(for: "native", answer: answer, promptID: next.id)
        let nextDeadline = ContinuousClock.now + .seconds(15)
        while model.paseoSendingSessionIDs.contains("native"), ContinuousClock.now < nextDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.paseoSubmittedAnswer(for: "native", promptID: next.id) != nil)
    }

    @Test func progressObservedDuringSendAppliesOnDeliveryAck() async throws {
        let mock = FollowthroughMock()
        await mock.setStall(true)
        let coordinator = PaseoQuestionCoordinator(call: { try await mock.call($0, $1) })
        let model = isolatedPaseoAppModel(coordinator)
        model.connectPaseoQuestions()
        coordinator.stop()
        await coordinator.poll()
        let prompt = try #require(model.state.session(id: "native")?.questionPrompt)
        model.answerQuestion(for: "native", answer: .init(answers: ["Choose": "One"]), promptID: prompt.id)
        let sendingDeadline = ContinuousClock.now + .seconds(15)
        while !(await mock.isSubmitWaiting), ContinuousClock.now < sendingDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let isSubmitWaiting = await mock.isSubmitWaiting
        if !isSubmitWaiting { await mock.releaseSubmit() }
        try #require(isSubmitWaiting)
        model.applyTrackedEvent(.activityUpdated(SessionActivityUpdated(
            sessionID: "native", summary: "Working", phase: .running, timestamp: .now)))
        #expect(model.paseoSuccesses["native"] == nil)
        await mock.releaseSubmit()
        let finishDeadline = ContinuousClock.now + .seconds(15)
        while model.paseoSendingSessionIDs.contains("native"), ContinuousClock.now < finishDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.state.session(id: "native")?.questionPrompt == nil)
        #expect(!model.paseoConfirmingResumeSessionIDs.contains("native"))
        #expect(model.paseoSuccesses["native"] == "Paseo側の再開を確認しました。")
    }

    @Test func bufferedProgressOnlySurvivesSuccessfulDeliveryOnTargetSession() async throws {
        let mock = FollowthroughMock()
        await mock.setStall(true)
        let coordinator = PaseoQuestionCoordinator(call: { try await mock.call($0, $1) })
        let model = isolatedPaseoAppModel(coordinator)
        model.connectPaseoQuestions()
        coordinator.stop()
        await coordinator.poll()
        let prompt = try #require(model.state.session(id: "native")?.questionPrompt)
        model.answerQuestion(for: "native", answer: .init(answers: ["Choose": "One"]), promptID: prompt.id)
        let sendingDeadline = ContinuousClock.now + .seconds(15)
        while !(await mock.isSubmitWaiting), ContinuousClock.now < sendingDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let isSubmitWaiting = await mock.isSubmitWaiting
        if !isSubmitWaiting { await mock.releaseSubmit() }
        try #require(isSubmitWaiting)
        model.applyTrackedEvent(.activityUpdated(SessionActivityUpdated(
            sessionID: "other-native", summary: "Wrong", phase: .running, timestamp: .now)))
        model.applyTrackedEvent(.activityUpdated(SessionActivityUpdated(
            sessionID: "native", summary: "Working", phase: .running, timestamp: .now)))
        await mock.setFail(true)
        await mock.releaseSubmit()
        let finishDeadline = ContinuousClock.now + .seconds(15)
        while model.paseoSendingSessionIDs.contains("native"), ContinuousClock.now < finishDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.state.session(id: "native")?.questionPrompt?.id == prompt.id)
        #expect(model.paseoConfirmingResumeSessionIDs.isEmpty)
        #expect(model.paseoErrors["native"] != nil)
        #expect(model.paseoSuccesses["native"] == nil)
    }
}
