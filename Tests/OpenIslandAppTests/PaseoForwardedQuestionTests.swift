import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

private actor ForwardedPaseoMock {
    var pending = true
    var parentIdentity = true
    var parentOwnRequest = false
    var parentApproval = false
    func setParentApproval(_ value: Bool) { parentOwnRequest = value; parentApproval = value }
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
        if id == "parent", parentApproval {
            snapshot["pendingPermissions"] = .array([.object(["id": .string("q-parent" + requestVersion), "name": .string("Bash"), "kind": .string("tool"), "input": .object(["command": .string("fixture read-only")])])])
        }
        return .object(["snapshot": .object(snapshot)])
    }
}

@MainActor struct PaseoForwardedQuestionTests {
    private func model(_ coordinator: PaseoQuestionCoordinator) -> AppModel {
        let defaults = UserDefaults(suiteName: "forwarded-paseo-\(UUID().uuidString)")!
        return isolatedPaseoAppModel(coordinator, settings: SettingsStore(store: PreferenceStore(suite: defaults)))
    }
    @Test func bridgeStartupFailureStillDiscoversSDKQuestionsInIsolatedRegistries() async throws {
        enum BridgeFailure: Error { case unavailable }
        let mock = ForwardedPaseoMock()
        let coordinator = PaseoQuestionCoordinator(call: { await mock.call($0, $1) })
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = isolatedPaseoAppModel(coordinator, registryDirectory: directory)
        model.startAgentConnections { throw BridgeFailure.unavailable }
        coordinator.stop()
        await coordinator.poll()
        #expect(!model.isBridgeReady)
        #expect(model.lastActionMessage.contains("Failed to start local bridge"))
        #expect(model.state.session(id: "parent-native")?.questionPrompt != nil)
        #expect(coordinator.questions["child-native"] != nil)
        model.discovery.scheduleClaudeSessionPersistence()
        let registry = ClaudeSessionRegistry(fileURL: directory.appendingPathComponent("claude.json"))
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !FileManager.default.fileExists(atPath: registry.fileURL.path), ContinuousClock.now < deadline { await Task.yield() }
        #expect(Set(try registry.load().map(\.sessionID)) == ["parent-native", "child-native"])
    }

    @Test func startupCacheMergePreservesAnAlreadyReceivedSDKQuestion() async throws {
        let mock = ForwardedPaseoMock()
        let coordinator = PaseoQuestionCoordinator(call: { await mock.call($0, $1) })
        let model = model(coordinator)
        model.connectPaseoQuestions(); coordinator.stop()
        await coordinator.poll()
        let question = try #require(coordinator.questions["child-native"])
        let parent = try #require(model.state.session(id: "parent-native"))
        var staleParent = parent
        staleParent.questionPrompt = nil
        staleParent.phase = .completed
        staleParent.updatedAt = .now.addingTimeInterval(10)
        let cachedCodex = AgentSession(id: "cached-codex", title: "Cached", tool: .codex,
            origin: .live, phase: .running, summary: "Cached", updatedAt: .now)
        model.discovery.applyStartupDiscoveryPayload(.init(
            codexRecords: [CodexTrackedSessionRecord(session: cachedCodex)], codexRecordsNeedPrune: false,
            claudeRecords: [ClaudeTrackedSessionRecord(session: staleParent)], claudeRecordsNeedPrune: false,
            openCodeRecords: [], openCodeRecordsNeedPrune: false,
            cursorRecords: [], cursorRecordsNeedPrune: false,
            discoveredCodexRecords: [], discoveredClaudeSessions: [], hooksBinaryURL: nil))
        var scanParent = parent
        scanParent.questionPrompt = nil
        scanParent.phase = .running
        scanParent.updatedAt = .now.addingTimeInterval(20)
        let merged = model.discovery.mergeDiscoveredSessions([scanParent])
        model.state = SessionState(sessions: merged)
        await coordinator.poll()
        #expect(Set(model.state.sessions.map(\.id)) == ["child-native", "parent-native", "cached-codex"])
        #expect(model.state.session(id: "parent-native")?.questionPrompt == question.prompt)
        #expect(model.state.session(id: "parent-native")?.jumpTarget == parent.jumpTarget)
        #expect(model.forwardedQuestionTargets["parent-native"] == "child-native")
        #expect(coordinator.questions["child-native"]?.input == question.input)
        model.answerQuestion(for: "parent-native", answer: .init(answer: "Yes"), promptID: question.prompt.id)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while model.paseoSendingSessionIDs.contains("parent-native"), ContinuousClock.now < deadline { await Task.yield() }
        #expect(await mock.sends == ["child"])
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
    @Test func exactParentBindingReplacesHookTitleWithoutChangingQuestionTarget() async throws {
        let mock = ForwardedPaseoMock()
        let coordinator = PaseoQuestionCoordinator(call: { await mock.call($0, $1) })
        let model = model(coordinator)
        model.state = SessionState(sessions: [AgentSession(id: "parent-native", title: "# AGENTS.md instructions",
            tool: .claudeCode, origin: .live, attachmentState: .attached, phase: .running,
            summary: "Hook", updatedAt: .now,
            jumpTarget: JumpTarget(terminalApp: "Paseo", workspaceName: "project", paneTitle: "hook")),
            AgentSession(id: "independent", title: "Independent conversation", tool: .claudeCode,
                origin: .live, attachmentState: .attached, phase: .running, summary: "", updatedAt: .now)])
        model.connectPaseoQuestions(); coordinator.stop()
        await coordinator.poll()
        #expect(model.state.session(id: "parent-native")?.title == "parent")
        #expect(model.state.session(id: "independent")?.title == "Independent conversation")
        #expect(model.forwardedPaseoQuestionSource(sessionID: "parent-native")?.childSessionID == "child-native")
        let prompt = try #require(model.state.session(id: "parent-native")?.questionPrompt)
        await coordinator.poll()
        #expect(model.state.session(id: "parent-native")?.questionPrompt?.id == prompt.id)
        #expect(model.state.session(id: "parent-native")?.title == "parent")
        model.answerQuestion(for: "parent-native", answer: .init(answer: "Yes"), promptID: prompt.id)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while model.paseoSendingSessionIDs.contains("parent-native"), ContinuousClock.now < deadline { await Task.yield() }
        #expect(await mock.sends == ["child"])
        #expect(model.state.session(id: "parent-native")?.title == "parent")
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

    @Test func parentApprovalKeepsChildPendingThenProjectsExactQuestionAfterResolution() async throws {
        let mock = ForwardedPaseoMock()
        await mock.setParentApproval(true)
        let coordinator = PaseoQuestionCoordinator(call: { await mock.call($0, $1) })
        let model = model(coordinator)
        model.connectPaseoQuestions(); coordinator.stop()
        await coordinator.poll()
        let childQuestion = try #require(coordinator.questions["child-native"])
        let parentApproval = try #require(model.state.session(id: "parent-native")?.permissionRequest)
        #expect(parentApproval.paseoContext?.agentID == "parent")
        #expect(model.state.session(id: "parent-native")?.phase == .waitingForApproval)
        #expect(model.forwardedQuestionTargets.isEmpty)
        #expect(Set(model.islandListSessions.map(\.id)) == ["parent-native"])
        #expect(coordinator.delegatedSessionIDs.contains("child-native"))
        #expect(await mock.sends.isEmpty)
        await mock.setParentApproval(false)
        await coordinator.poll()
        #expect(model.state.session(id: "parent-native")?.permissionRequest == nil)
        #expect(model.state.session(id: "parent-native")?.questionPrompt?.id == childQuestion.prompt.id)
        #expect(coordinator.questions["child-native"]?.requestID == childQuestion.requestID)
        #expect(model.forwardedQuestionTargets["parent-native"] == "child-native")
        model.answerQuestion(for: "parent-native", answer: .init(answer: "Yes"), promptID: childQuestion.prompt.id)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while model.paseoSendingSessionIDs.contains("parent-native"), ContinuousClock.now < deadline { await Task.yield() }
        #expect(await mock.sends == ["child"])
        #expect(coordinator.requests["child-native"] == nil)
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
