import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

private actor PaseoWiringMock {
    var hasQuestion = true
    var fail = false
    var sends = 0
    func setFailure(_ value: Bool) { fail = value }
    func clear() { hasQuestion = false }
    func call(_ name: String, _ input: ClaudeHookJSONValue) throws -> ClaudeHookJSONValue {
        let snapshot: ClaudeHookJSONValue = .object([
            "id": .string("paseo-agent"), "provider": .string("claude"), "title": .string("Paseo test"), "cwd": .string("/project"),
            "persistence": .object(["sessionId": .string("exact-native-id")]),
            "pendingPermissions": .array(hasQuestion ? [.object([
                "id": .string("question-request"), "name": .string("AskUserQuestion"),
                "input": .object(["questions": .array([.object([
                    "question": .string("Choose"), "header": .string("Choice"),
                    "options": .array([.object(["label": .string("One")])])
                ])])])
            ])] : [])
        ])
        if name == "list_pending_permissions" {
            return .object(["permissions": .array(hasQuestion ? [.object([
                "agentId": .string("paseo-agent"), "request": .object(["id": .string("question-request"), "name": .string("AskUserQuestion")])
            ])] : [])])
        }
        if name == "get_agent_status" { return .object(["snapshot": snapshot]) }
        sends += 1
        if fail { throw PaseoQuestionError.invalidResponse }
        hasQuestion = false
        return .object(["success": .boolean(true)])
    }
}

@MainActor
struct PaseoQuestionWiringTests {
    private func waitForSubmission(_ model: AppModel, sessionID: String) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while model.paseoSendingSessionIDs.contains(sessionID), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        try #require(!model.paseoSendingSessionIDs.contains(sessionID))
    }

    @Test func questionAppearsInAppModelAndOnlySuccessfulSendClearsWaiting() async throws {
        let mock = PaseoWiringMock()
        let coordinator = PaseoQuestionCoordinator(call: { try await mock.call($0, $1) })
        let suiteName = "paseo-wiring-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(settings: SettingsStore(store: PreferenceStore(suite: defaults)), paseoQuestions: coordinator)
        model.connectPaseoQuestions()
        coordinator.stop()
        await coordinator.poll()
        let session = try #require(model.state.session(id: "exact-native-id"))
        #expect(session.jumpTarget?.terminalApp == "Paseo")
        #expect(session.phase == .waitingForAnswer)
        #expect(session.questionPrompt?.questions.first?.question == "Choose")
        await mock.setFailure(true)
        model.answerQuestion(for: session.id, answer: .init(answers: ["Choose": "One"]))
        try await waitForSubmission(model, sessionID: session.id)
        #expect(model.state.session(id: session.id)?.questionPrompt != nil)
        #expect(model.state.session(id: session.id)?.phase == .waitingForAnswer)
        await mock.setFailure(false)
        model.answerQuestion(for: session.id, answer: .init(answers: ["Choose": "One"]))
        try await waitForSubmission(model, sessionID: session.id)
        #expect(model.state.session(id: session.id)?.questionPrompt == nil)
        #expect(model.state.session(id: session.id)?.phase == .running)
        #expect(await mock.sends == 2)
    }

    @Test func externalAnswerRemovesOnlyMatchingQuestion() async throws {
        let mock = PaseoWiringMock()
        let coordinator = PaseoQuestionCoordinator(call: { try await mock.call($0, $1) })
        let model = AppModel(paseoQuestions: coordinator)
        model.connectPaseoQuestions()
        coordinator.stop()
        await coordinator.poll()
        #expect(model.state.session(id: "exact-native-id")?.questionPrompt != nil)
        await mock.clear()
        await coordinator.poll()
        #expect(model.state.session(id: "exact-native-id")?.questionPrompt == nil)
        #expect(await mock.sends == 0)
    }
}
