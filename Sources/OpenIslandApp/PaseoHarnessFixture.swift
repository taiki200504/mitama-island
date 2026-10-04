import Foundation
import OpenIslandCore

/// Isolated fixture: no permission response reaches the real Paseo daemon.
actor PaseoHarnessFixture {
    enum Variant: String { case basic, long, child, unknown }
    static var variant: Variant {
        Variant(rawValue: ProcessInfo.processInfo.environment["OPEN_ISLAND_PASEO_MOCK_VARIANT"] ?? "") ?? .basic
    }
    let isQuestion: Bool
    let variant: Variant
    var pending = true
    var failOnce: Bool
    private let createdAt = Date.now
    private let replacementDelay: TimeInterval?
    init(isQuestion: Bool, variant: Variant? = nil) {
        self.isQuestion = isQuestion
        self.variant = variant ?? Self.variant
        failOnce = ProcessInfo.processInfo.environment["OPEN_ISLAND_PASEO_MOCK_FAIL_ONCE"] == "true"
        let delay = Double(ProcessInfo.processInfo.environment["OPEN_ISLAND_PASEO_MOCK_REPLACE_QUESTION_AFTER_SECONDS"] ?? "")
        replacementDelay = delay.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }
    func call(_ name: String, _ input: ClaudeHookJSONValue) async throws -> ClaudeHookJSONValue {
        let provider = isQuestion ? "codex" : "claude"
        let isReplacement = isQuestion && replacementDelay.map { Date.now.timeIntervalSince(createdAt) >= $0 } == true
        let basicQuestions: ClaudeHookJSONValue = .array([.object([
            "id": .string("0"), "header": .string("Question 1"), "question": .string("次の作業の進め方を選んでください。"),
            "options": .array([.object(["label": .string("現在の設定を維持して続ける")]), .object(["label": .string("Paseoで詳細を確認する")])])
        ])])
        let extendedQuestions: ClaudeHookJSONValue = .array([
            .object(["id": .string("approach"), "header": .string("進め方"),
                "question": .string(String(repeating: "この画面はローカルの表示確認専用です。長文が折り返され、選択肢と送信操作が画面の中で読めることを確認してください。", count: 5)),
                "options": .array((1...8).map { number in .object([
                    "label": .string("選択肢 \(number)：現在の内容を確認して続ける"),
                    "description": .string("説明文を省略せず読めるか、スクロールして最後の選択肢まで届くかを確認します。")
                ]) })]),
            .object(["id": .string("checks"), "header": .string("複数選択"), "multiSelect": .boolean(true),
                "question": .string("確認した項目を複数選んでください。"),
                "options": .array(["文章", "選択肢", "送信後の表示"].map { .object(["label": .string($0)]) })]),
            .object(["id": .string("notes"), "header": .string("自由入力"),
                "question": .string("選択肢のない質問への回答を入力してください。"), "options": .array([])])
        ])
        let questions = variant == .basic ? basicQuestions : extendedQuestions
        let agentID = variant == .child ? "fixture-child" : "fixture-agent"
        let request: ClaudeHookJSONValue = .object([
            "id": .string(isReplacement ? "fixture-request-next" : "fixture-request"), "provider": .string(provider),
            "name": .string(variant == .unknown ? "future_provider_question" : (isQuestion ? "request_user_input_async" : "Bash")),
            "kind": .string(isQuestion ? "question" : "tool"),
            "metadata": .object(["toolUseId": .string("fixture-tool")]),
            "input": variant == .unknown ? .object(["schemaVersion": .number(999), "message": .string("未知の質問形式：回答せずPaseoで確認してください。")]) : (isQuestion ? .object(["questions": questions]) : .object(["command": .string("echo 'Paseo の許可テスト'")]))
        ])
        if name == "list_pending_permissions" {
            return .object(["permissions": .array(pending ? [.object(["agentId": .string(agentID), "request": request])] : [])])
        }
        if name == "list_agents" {
            let ids = variant == .child ? ["fixture-parent", "fixture-child"] : ["fixture-agent"]
            return .object(["agents": .array(ids.map { .object(["id": .string($0)]) })])
        }
        if name == "get_agent_status" {
            guard case let .object(arguments) = input, case let .string(requestedID)? = arguments["agentId"] else {
                throw PaseoQuestionError.invalidResponse
            }
            let isParent = variant == .child && requestedID == "fixture-parent"
            guard requestedID == agentID || isParent else { throw PaseoQuestionError.expired }
            return .object(["snapshot": .object([
                "id": .string(requestedID), "provider": .string(provider), "status": .string("running"),
                "archivedAt": .null, "providerUnavailable": .boolean(false),
                "labels": variant == .child && !isParent ? .object(["paseo.parent-agent-id": .string("fixture-parent")]) : .object([:]),
                "title": .string(isParent ? "親：表示確認の担当" : (isReplacement ? "Paseo 表示確認（質問更新）" : "Paseo 表示確認")), "cwd": .string("paseo-sandbox"),
                "currentModeId": .string(isQuestion ? "full-access" : "bypassPermissions"),
                "availableModes": .array([.object(["id": .string(isQuestion ? "full-access" : "bypassPermissions"),
                                                  "label": .string(isQuestion ? "Full access" : "Bypass permissions")])]),
                "persistence": .object(["provider": .string(provider), "sessionId": .string(isParent ? "paseo-fixture-parent" : "paseo-fixture-session")]),
                "pendingPermissions": .array(pending && !isParent ? [request] : [])
            ])])
        }
        guard name == "respond_to_permission" else { throw PaseoQuestionError.invalidResponse }
        guard case let .object(arguments) = input,
              arguments["agentId"] == .string(agentID), arguments["requestId"] == .string("fixture-request") else {
            throw PaseoQuestionError.expired
        }
        try await Task.sleep(for: .milliseconds(800))
        if failOnce { failOnce = false; throw PaseoQuestionError.invalidResponse }
        pending = false
        return .object(["success": .boolean(true)])
    }

    @MainActor static func coordinator(isQuestion: Bool) -> PaseoQuestionCoordinator {
        let fixture = PaseoHarnessFixture(isQuestion: isQuestion)
        return PaseoQuestionCoordinator(call: { try await fixture.call($0, $1) })
    }
    static func sessions(isQuestion: Bool, now: Date) -> [AgentSession] {
        let child = session(isQuestion: isQuestion, now: now)
        guard variant == .child else { return [child] }
        let parent = AgentSession(id: "paseo-fixture-parent", title: "親：表示確認の担当", tool: .codex,
            origin: .demo, attachmentState: .attached, phase: .running,
            summary: "子の質問を親へまとめて表示する確認", updatedAt: now,
            jumpTarget: JumpTarget(terminalApp: "Paseo", workspaceName: "paseo-sandbox", paneTitle: "親",
                terminalSessionID: "paseo-fixture-parent", paseoAgentID: "fixture-parent", paseoServerID: "fixture-server"))
        return [parent, child]
    }
    static func session(isQuestion: Bool, now: Date) -> AgentSession {
        AgentSession(id: "paseo-fixture-session", title: "Paseo 表示確認", tool: isQuestion ? .codex : .claudeCode,
            origin: .demo, attachmentState: .attached, phase: isQuestion ? .waitingForAnswer : .waitingForApproval,
            summary: "Paseoの表示と送信の確認（実際のコマンドは実行しません）", updatedAt: now,
            jumpTarget: JumpTarget(terminalApp: "Paseo", workspaceName: "paseo-sandbox", paneTitle: "表示確認",
                                  terminalSessionID: "paseo-fixture-session", paseoAgentID: variant == .child ? "fixture-child" : "fixture-agent", paseoServerID: "fixture-server"))
    }
}
