import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

private actor ChildPermissionMock {
    var parents: [String: String]
    var titles: [String: String]
    var pendingIDs: [String]
    var escalation: String?
    var statusCalls: [String: Int] = [:]
    var responses: [String] = []
    var provider = "claude"

    init(parents: [String: String] = ["child": "parent"],
         titles: [String: String] = ["child": "子の題", "parent": "親の題"],
         pendingIDs: [String] = ["child"]) {
        self.parents = parents
        self.titles = titles
        self.pendingIDs = pendingIDs
    }

    func escalate(_ requestID: String?) { escalation = requestID }
    func clear() { pendingIDs = [] }
    func useCodex() { provider = "codex" }

    func call(_ name: String, _ input: ClaudeHookJSONValue) throws -> ClaudeHookJSONValue {
        if name == "list_pending_permissions" {
            return .object(["permissions": .array(pendingIDs.map {
                .object(["agentId": .string($0), "request": .object(["id": .string("request-" + $0)])])
            })])
        }
        guard case let .object(arguments) = input, case let .string(id)? = arguments["agentId"] else {
            throw PaseoQuestionError.invalidResponse
        }
        if name == "respond_to_permission" {
            responses.append(id)
            pendingIDs.removeAll { $0 == id }
            return .object(["success": .boolean(true)])
        }
        guard name == "get_agent_status" else { throw PaseoQuestionError.invalidResponse }
        statusCalls[id, default: 0] += 1
        var labels: [String: ClaudeHookJSONValue] = [:]
        if let parent = parents[id] { labels["paseo.parent-agent-id"] = .string(parent) }
        if let escalation { labels["approval.escalate"] = .string(escalation) }
        var snapshot: [String: ClaudeHookJSONValue] = [
            "id": .string(id), "provider": .string(provider), "status": .string("running"),
            "cwd": .string("/project"), "labels": .object(labels),
            "persistence": .object(["sessionId": .string("native-" + id)]),
            "pendingPermissions": .array(pendingIDs.contains(id) ? [.object([
                "id": .string("request-" + id), "name": .string("Bash"), "kind": .string("tool"),
                "input": .object(["command": .string("echo demo")])
            ])] : [])
        ]
        if let title = titles[id] { snapshot["title"] = .string(title) }
        return .object(["snapshot": .object(snapshot)])
    }
}

@MainActor
struct PaseoChildPermissionTests {
    private func model(_ mock: ChildPermissionMock) -> (AppModel, PaseoQuestionCoordinator) {
        let coordinator = PaseoQuestionCoordinator(call: { try await mock.call($0, $1) }, providerAliases: [:])
        let model = isolatedPaseoAppModel(coordinator)
        model.suppressFrontmostNotifications = false
        model.connectPaseoQuestions()
        coordinator.stop()
        return (model, coordinator)
    }

    @Test func runningParentsChildPermissionIsActionableOnFirstPoll() async throws {
        let (model, coordinator) = model(ChildPermissionMock())
        await coordinator.poll()
        #expect(coordinator.delegatedSessionIDs.isEmpty)
        #expect(model.focusedSession?.id == "native-child")
        #expect(model.activeIslandCardSession?.id == "native-child")
        #expect(model.islandSurfaceAwaitsUserAction)
        let permission = try #require(model.activeIslandCardSession?.permissionRequest)
        #expect(permission.summary == "子の承認: 子の題（親: 親の題）\necho demo")
        #expect(model.islandListSessions.map(\.id) == ["native-child"])
    }

    @Test func grandchildPermissionShowsBothAncestorsOnFirstPoll() async throws {
        let mock = ChildPermissionMock(parents: ["grandchild": "child", "child": "parent"],
            titles: ["grandchild": "孫の題", "child": "子の題", "parent": "親の題"], pendingIDs: ["grandchild"])
        let (model, coordinator) = model(mock)
        await coordinator.poll()
        #expect(model.focusedSession?.id == "native-grandchild")
        #expect(model.activeIslandCardSession?.id == "native-grandchild")
        #expect(model.islandSurfaceAwaitsUserAction)
        #expect(model.activeIslandCardSession?.permissionRequest?.summary == "子の承認: 孫の題（親: 子の題 ← 親の題）\necho demo")
    }

    @Test func sdkPermissionIsVisibleEvenWithLocalCodexParentMetadata() async throws {
        let mock = ChildPermissionMock()
        await mock.useCodex()
        let (model, coordinator) = model(mock)
        await coordinator.poll()
        var child = try #require(model.state.session(id: "native-child"))
        child.codexMetadata = CodexSessionMetadata(parentThreadID: "native-parent")
        var parent = AgentSession(id: "native-parent", title: "親の題", tool: .codex,
            origin: .live, attachmentState: .attached, phase: .running, summary: "Running", updatedAt: .now)
        parent.isProcessAlive = true
        model.state = SessionState(sessions: [child, parent])
        #expect(model.focusedSession?.id == "native-child")
        #expect(model.activeIslandCardSession?.id == "native-child")
        #expect(model.islandSurfaceAwaitsUserAction)
        #expect(model.islandListSessions.contains(where: { $0.id == "native-child" }))
    }

    @Test func matchingEscalationUpdatesSameCardAndOldRequestDoesNotEscalate() async throws {
        let mock = ChildPermissionMock()
        let (model, coordinator) = model(mock)
        await coordinator.poll()
        let original = try #require(model.state.session(id: "native-child")?.permissionRequest)
        model.notchClose()
        await mock.escalate("request-child")
        await coordinator.poll()
        let escalated = try #require(model.state.session(id: "native-child")?.permissionRequest)
        #expect(escalated.summary == "親が本人へ上げた: 子の題（親: 親の題）\necho demo")
        #expect(escalated.id == original.id)
        #expect(model.notchStatus == .closed)
        await mock.escalate("old-request")
        await coordinator.poll()
        #expect(model.state.session(id: "native-child")?.permissionRequest?.summary == original.summary)
        #expect(model.state.session(id: "native-child")?.permissionRequest?.id == original.id)
        #expect(model.notchStatus == .closed)
    }

    @Test func externalChildResolutionRemovesTheCardWithoutResponding() async throws {
        let mock = ChildPermissionMock()
        let (model, coordinator) = model(mock)
        await coordinator.poll()
        #expect(model.islandSurfaceAwaitsUserAction)
        await mock.clear()
        await coordinator.poll()
        #expect(model.state.session(id: "native-child")?.permissionRequest == nil)
        #expect(model.pendingApprovalSessions.isEmpty)
        #expect(!model.islandSurfaceAwaitsUserAction)
        #expect(await mock.responses.isEmpty)
    }

    @Test func childApprovalStillUsesRespondToPermission() async throws {
        let mock = ChildPermissionMock()
        let (model, coordinator) = model(mock)
        await coordinator.poll()
        let request = try #require(model.activeIslandCardSession?.permissionRequest)
        model.approvePermission(for: "native-child", action: .allowOnce, playsSound: false, expectedRequestID: request.id)
        let deadline = ContinuousClock.now + .seconds(15)
        while model.paseoSendingSessionIDs.contains("native-child"), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(!model.paseoSendingSessionIDs.contains("native-child"))
        #expect(await mock.responses == ["child"])
        #expect(model.state.session(id: "native-child")?.permissionRequest?.id == request.id)
        model.applyTrackedEvent(.activityUpdated(SessionActivityUpdated(
            sessionID: "native-child", summary: "Resumed", phase: .running, timestamp: .now)))
        #expect(model.state.session(id: "native-child")?.permissionRequest == nil)
    }

    @Test func childPermissionsKeepRootPresentationAndAutoResponseRules() async throws {
        let childMock = ChildPermissionMock()
        let rootMock = ChildPermissionMock(parents: [:])
        let (child, childCoordinator) = model(childMock)
        let (root, rootCoordinator) = model(rootMock)
        for model in [child, root] {
            model.settings.autoResponse.addRule(AutoResponseRule(field: .workingDirectory, match: .equals,
                pattern: "/project", behavior: .allowOnce))
        }
        await childCoordinator.poll()
        await rootCoordinator.poll()
        #expect(child.notchStatus == root.notchStatus)
        #expect(child.islandSurface == root.islandSurface)
        #expect(child.islandSurfaceAwaitsUserAction == root.islandSurfaceAwaitsUserAction)
        #expect(await childMock.responses.isEmpty)
        #expect(await rootMock.responses.isEmpty)
    }

    @Test func ancestorChainIsBoundedAndMissingTitlesUseShortIDs() async throws {
        let mock = ChildPermissionMock(parents: ["child": "ancestor-one", "ancestor-one": "ancestor-two",
            "ancestor-two": "ancestor-three", "ancestor-three": "ancestor-four"], titles: [:])
        let (_, coordinator) = model(mock)
        await coordinator.poll()
        #expect(coordinator.requests["native-child"]?.permission?.summary ==
            "子の承認: child（親: ancestor ← ancestor ← ancestor）\necho demo")
        #expect(await mock.statusCalls["ancestor-four"] == nil)
    }

    @Test func sharedAncestorsAreFetchedOnceAndKnownBindingsAreReused() async throws {
        let mock = ChildPermissionMock(parents: ["child": "parent", "sibling": "parent"], pendingIDs: ["child", "sibling"])
        let (_, coordinator) = model(mock)
        await coordinator.poll()
        #expect(await mock.statusCalls["parent"] == 1)
        await coordinator.poll()
        #expect(await mock.statusCalls["parent"] == 1)
        #expect(await mock.statusCalls["child"] == 2)
        #expect(await mock.statusCalls["sibling"] == 2)
    }
}
