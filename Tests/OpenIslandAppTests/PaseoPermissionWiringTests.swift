import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

private actor PaseoApprovalMock {
    var fail = false
    var requestID = "request-1"
    var sends = 0
    var pending = true
    func setFailure(_ value: Bool) { fail = value }
    func advance() { requestID = "request-2" }
    func clear() { pending = false }
    func call(_ name: String, _ input: ClaudeHookJSONValue) throws -> ClaudeHookJSONValue {
        if name == "list_pending_permissions" {
            return .object(["permissions": .array(pending ? [.object([
                "agentId": .string("paseo-agent"), "request": .object(["id": .string(requestID)])
            ])] : [])])
        }
        if name == "get_agent_status" {
            return .object(["snapshot": .object([
                "id": .string("paseo-agent"), "provider": .string("claude"), "cwd": .string("/project"),
                "title": .string("Approval"), "status": .string("running"),
                "currentModeId": .string("bypassPermissions"),
                "persistence": .object(["provider": .string("claude"), "sessionId": .string("native")]),
                "pendingPermissions": .array([.object([
                    "id": .string(requestID), "provider": .string("claude"), "name": .string("Bash"), "kind": .string("tool"),
                    "input": .object(["command": .string("echo demo")]), "metadata": .object(["toolUseId": .string("call")])
                ])])
            ])])
        }
        sends += 1
        if fail { throw PaseoQuestionError.invalidResponse }
        return .object(["success": .boolean(true)])
    }
}

@MainActor
struct PaseoPermissionWiringTests {
    private func waitForSubmission(_ model: AppModel, sessionID: String) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while model.paseoSendingSessionIDs.contains(sessionID), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        try #require(!model.paseoSendingSessionIDs.contains(sessionID))
    }

    private func model(_ coordinator: PaseoQuestionCoordinator) -> AppModel {
        let defaults = UserDefaults(suiteName: "paseo-approval-\(UUID().uuidString)")!
        return isolatedPaseoAppModel(coordinator, settings: SettingsStore(store: PreferenceStore(suite: defaults)))
    }

    @Test func bothApprovalOverloadsUseSDKAndFailureKeepsCard() async throws {
        let mock = PaseoApprovalMock()
        let coordinator = PaseoQuestionCoordinator(call: { try await mock.call($0, $1) })
        let model = model(coordinator)
        model.connectPaseoQuestions(); coordinator.stop()
        await coordinator.poll()
        let request = try #require(model.state.session(id: "native")?.permissionRequest)
        #expect(request.paseoContext?.currentModeID == "bypassPermissions")
        await mock.setFailure(true)
        model.approvePermission(for: "native", approved: true)
        try await waitForSubmission(model, sessionID: "native")
        #expect(model.state.session(id: "native")?.permissionRequest?.id == request.id)
        #expect(model.paseoErrors["native"] != nil)
        #expect(model.paseoSendingSessionIDs.isEmpty)
        await mock.setFailure(false)
        model.approvePermission(for: "native", action: .deny, expectedRequestID: request.id)
        try await waitForSubmission(model, sessionID: "native")
        #expect(model.state.session(id: "native")?.permissionRequest == nil)
        #expect(model.paseoSuccesses["native"] != nil)
        #expect(await mock.sends == 2)
    }

    @Test func staleButtonsAndBatchDoNotSubmitPaseoRequests() async throws {
        let mock = PaseoApprovalMock()
        let coordinator = PaseoQuestionCoordinator(call: { try await mock.call($0, $1) })
        let model = model(coordinator)
        model.connectPaseoQuestions(); coordinator.stop()
        await coordinator.poll()
        let old = try #require(model.state.session(id: "native")?.permissionRequest)
        await mock.advance()
        await coordinator.poll()
        model.approvePermission(for: "native", action: .allowOnce, expectedRequestID: old.id)
        model.resolveAllPendingApprovals(.allowOnce)
        try await Task.sleep(for: .milliseconds(50))
        #expect(await mock.sends == 0)
        #expect(model.state.session(id: "native")?.permissionRequest?.paseoContext?.requestID == "request-2")
    }

    @Test func externalResolutionClearsOnlyTheKnownSDKCardWithoutGranting() async throws {
        let mock = PaseoApprovalMock()
        let coordinator = PaseoQuestionCoordinator(call: { try await mock.call($0, $1) })
        let model = model(coordinator)
        model.connectPaseoQuestions(); coordinator.stop()
        await coordinator.poll()
        #expect(model.state.session(id: "native")?.permissionRequest != nil)
        await mock.clear()
        await coordinator.poll()
        #expect(model.state.session(id: "native")?.permissionRequest == nil)
        #expect(await mock.sends == 0)
    }

    @Test func sdkCardCannotFallBackToAnUnobservedHookAndDisappear() async throws {
        let coordinator = PaseoQuestionCoordinator(call: { _, _ in throw PaseoQuestionError.invalidResponse })
        let model = model(coordinator)
        let context = PaseoPermissionContext(agentID: "agent", requestID: "expired", provider: "claude", kind: "tool",
                                             currentModeID: "bypassPermissions", currentModeLabel: "Bypass", actions: [])
        let request = PermissionRequest(title: "実行の許可", summary: "echo demo", affectedPath: "/project", paseoContext: context)
        model.state = SessionState(sessions: [AgentSession(id: "native", title: "Test", tool: .claudeCode,
            attachmentState: .attached, phase: .waitingForApproval, summary: "Pending", updatedAt: .now,
            permissionRequest: request, jumpTarget: JumpTarget(terminalApp: "Paseo", workspaceName: "Project", paneTitle: "Test"))])
        model.approvePermission(for: "native", approved: true)
        #expect(model.state.session(id: "native")?.permissionRequest?.id == request.id)
        #expect(model.paseoErrors["native"] != nil)
    }
}
