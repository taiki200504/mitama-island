import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

private actor ForwardedPaseoMock {
    var pending = true
    var parentIdentity = true
    var parentOwnRequest = false
    var sends: [String] = []
    var childID = "child"
    var requestVersion = "1"
    func nextChild() { childID = "child-b"; requestVersion = "2" }
    func configure(identity: Bool = true, own: Bool = false) { parentIdentity = identity; parentOwnRequest = own }
    func call(_ name: String, _ input: ClaudeHookJSONValue) -> ClaudeHookJSONValue {
        if name == "respond_to_permission" {
            if case let .object(args) = input, case let .string(id)? = args["agentId"] { sends.append(id) }
            pending = false
            return .object(["success": .boolean(true)])
        }
        if name == "list_pending_permissions" {
            let ids = (pending ? [childID] : []) + (parentOwnRequest ? ["parent"] : [])
            return .object(["permissions": .array(ids.map { .object(["agentId": .string($0), "request": .object(["id": .string("q-" + $0 + requestVersion)])]) })])
        }
        guard case let .object(args) = input, case let .string(id)? = args["agentId"] else { return .null }
        var snapshot: [String: ClaudeHookJSONValue] = ["id": .string(id), "provider": .string("claude"), "title": .string(id), "cwd": .string("/project"), "status": .string("running")]
        if id == childID || parentIdentity { snapshot["persistence"] = .object(["sessionId": .string(id + "-native"), "nativeHandle": .string(id + "-native")]) }
        if id == childID { snapshot["labels"] = .object(["paseo.parent-agent-id": .string("parent")]) }
        let hasQuestion = id == childID ? pending : parentOwnRequest
        snapshot["pendingPermissions"] = .array(hasQuestion ? [.object(["id": .string("q-" + id + requestVersion), "name": .string("AskUserQuestion"), "kind": .string("question"), "input": .object(["questions": .array([.object(["question": .string("Choose"), "header": .string("Choice")])])])])] : [])
        return .object(["snapshot": .object(snapshot)])
    }
}

@MainActor struct PaseoForwardedQuestionTests {
    private func model(_ coordinator: PaseoQuestionCoordinator) -> AppModel {
        let defaults = UserDefaults(suiteName: "forwarded-paseo-\(UUID().uuidString)")!
        return AppModel(settings: SettingsStore(store: PreferenceStore(suite: defaults)), paseoQuestions: coordinator)
    }
    @Test func childQuestionProjectsAndAnswersChildOnly() async throws {
        let mock = ForwardedPaseoMock()
        let coordinator = PaseoQuestionCoordinator(call: { await mock.call($0, $1) })
        let model = model(coordinator)
        model.connectPaseoQuestions(); coordinator.stop()
        await coordinator.poll()
        let prompt = try #require(model.state.session(id: "parent-native")?.questionPrompt)
        #expect(model.forwardedPaseoQuestionSource(sessionID: "parent-native")?.childSessionID == "child-native")
        #expect(model.state.session(id: "parent-native")?.jumpTarget?.paseoAgentID == "parent")
        model.answerQuestion(for: "parent-native", answer: .init(answer: "Yes"), promptID: UUID())
        #expect(await mock.sends.isEmpty)
        model.answerQuestion(for: "parent-native", answer: .init(answer: "Yes"), promptID: prompt.id)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while model.paseoSendingSessionIDs.contains("parent-native"), ContinuousClock.now < deadline { await Task.yield() }
        #expect(await mock.sends == ["child"])
        #expect(model.forwardedQuestionTargets.isEmpty)
        #expect(model.state.session(id: "parent-native")?.phase == .running)
    }
    @Test func sameQuestionKeepsRetryStateButNextChildClearsDisplayState() async throws {
        let mock = ForwardedPaseoMock()
        let coordinator = PaseoQuestionCoordinator(call: { await mock.call($0, $1) })
        let model = model(coordinator)
        model.connectPaseoQuestions(); coordinator.stop()
        await coordinator.poll()
        let first = try #require(model.state.session(id: "parent-native")?.questionPrompt)
        model.paseoErrors["parent-native"] = "retry"
        model.paseoSuccesses["parent-native"] = "old success"
        await coordinator.poll()
        #expect(model.state.session(id: "parent-native")?.questionPrompt?.id == first.id)
        #expect(model.paseoErrors["parent-native"] == "retry")
        model.paseoSendingSessionIDs.insert("parent-native")
        await mock.nextChild()
        await coordinator.poll()
        let next = try #require(model.state.session(id: "parent-native")?.questionPrompt)
        #expect(next.id != first.id)
        #expect(model.forwardedQuestionTargets["parent-native"] == "child-b-native")
        #expect(model.paseoErrors["parent-native"] == nil)
        #expect(model.paseoSuccesses["parent-native"] == nil)
        #expect(!model.paseoSendingSessionIDs.contains("parent-native"))
        #expect(Set(model.islandListSessions.map(\.id)) == ["parent-native"])
        #expect(model.liveAttentionCount == 1)
        model.answerQuestion(for: "parent-native", answer: .init(answer: "Yes"), promptID: first.id)
        #expect(await mock.sends.isEmpty)
    }

    @Test func unknownParentIdentityLeavesChildVisibleAndOwnQuestionWins() async throws {
        let mock = ForwardedPaseoMock()
        await mock.configure(identity: false)
        let coordinator = PaseoQuestionCoordinator(call: { await mock.call($0, $1) })
        let model = model(coordinator)
        model.connectPaseoQuestions(); coordinator.stop()
        await coordinator.poll()
        #expect(!coordinator.delegatedSessionIDs.contains("child-native"))
        #expect(model.forwardedQuestionTargets.isEmpty)
        await mock.configure(own: true)
        await coordinator.poll()
        #expect(model.forwardedQuestionTargets.isEmpty)
        #expect(model.state.session(id: "parent-native")?.questionPrompt?.id == coordinator.questions["parent-native"]?.prompt.id)
    }
}
