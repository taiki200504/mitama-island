import Foundation
import OpenIslandCore

/// Isolated fixture: no permission response reaches the real Paseo daemon.
actor PaseoHarnessFixture {
    let isQuestion: Bool
    var pending = true
    var failOnce: Bool
    init(isQuestion: Bool) {
        self.isQuestion = isQuestion
        failOnce = ProcessInfo.processInfo.environment["OPEN_ISLAND_PASEO_MOCK_FAIL_ONCE"] == "true"
    }
    func call(_ name: String, _ input: ClaudeHookJSONValue) async throws -> ClaudeHookJSONValue {
        let provider = isQuestion ? "codex" : "claude"
        let questions: ClaudeHookJSONValue = .array([.object([
            "id": .string("0"), "header": .string("Question 1"), "question": .string("次の作業の進め方を選んでください。"),
            "options": .array([.object(["label": .string("現在の設定を維持して続ける")]), .object(["label": .string("Paseoで詳細を確認する")])])
        ])])
        let request: ClaudeHookJSONValue = .object([
            "id": .string("fixture-request"), "provider": .string(provider),
            "name": .string(isQuestion ? "request_user_input_async" : "Bash"),
            "kind": .string(isQuestion ? "question" : "tool"),
            "metadata": .object(["toolUseId": .string("fixture-tool")]),
            "input": isQuestion ? .object(["questions": questions]) : .object(["command": .string("echo 'Paseo の許可テスト'")])
        ])
        if name == "list_pending_permissions" {
            return .object(["permissions": .array(pending ? [.object(["agentId": .string("fixture-agent"), "request": request])] : [])])
        }
        if name == "get_agent_status" {
            return .object(["snapshot": .object([
                "id": .string("fixture-agent"), "provider": .string(provider), "status": .string("running"),
                "title": .string("Paseo 表示確認"), "cwd": .string("paseo-sandbox"),
                "currentModeId": .string(isQuestion ? "full-access" : "bypassPermissions"),
                "availableModes": .array([.object(["id": .string(isQuestion ? "full-access" : "bypassPermissions"),
                                                  "label": .string(isQuestion ? "Full access" : "Bypass permissions")])]),
                "persistence": .object(["provider": .string(provider), "sessionId": .string("paseo-fixture-session")]),
                "pendingPermissions": .array(pending ? [request] : [])
            ])])
        }
        guard name == "respond_to_permission" else { throw PaseoQuestionError.invalidResponse }
        try await Task.sleep(for: .milliseconds(800))
        if failOnce { failOnce = false; throw PaseoQuestionError.invalidResponse }
        pending = false
        return .object(["success": .boolean(true)])
    }

    @MainActor static func coordinator(isQuestion: Bool) -> PaseoQuestionCoordinator {
        let fixture = PaseoHarnessFixture(isQuestion: isQuestion)
        return PaseoQuestionCoordinator(call: { try await fixture.call($0, $1) })
    }
    static func session(isQuestion: Bool, now: Date) -> AgentSession {
        AgentSession(id: "paseo-fixture-session", title: "Paseo 表示確認", tool: isQuestion ? .codex : .claudeCode,
            origin: .demo, attachmentState: .attached, phase: isQuestion ? .waitingForAnswer : .waitingForApproval,
            summary: "Paseoの表示と送信の確認（実際のコマンドは実行しません）", updatedAt: now,
            jumpTarget: JumpTarget(terminalApp: "Paseo", workspaceName: "paseo-sandbox", paneTitle: "表示確認",
                                  terminalSessionID: "paseo-fixture-session", paseoAgentID: "fixture-agent", paseoServerID: "fixture-server"))
    }
}
