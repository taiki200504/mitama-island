import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
struct IslandDecisionPresentationTests {
    private func session(_ id: String, phase: SessionPhase, request: PermissionRequest? = nil) -> AgentSession {
        AgentSession(id: id, title: "同じワークスペース内の会話 " + id, tool: .claudeCode,
            origin: .demo, attachmentState: .attached, phase: phase, summary: "Test",
            updatedAt: .now, permissionRequest: request,
            jumpTarget: JumpTarget(terminalApp: "Paseo", workspaceName: "shared-project", paneTitle: id))
    }

    @Test func decisionsPrecedeActivityWithoutLosingOrDuplicatingSessions() {
        let input = [session("done", phase: .completed), session("running", phase: .running),
                     session("question", phase: .waitingForAnswer), session("approval", phase: .waitingForApproval)]
        let ordered = IslandSessionPriority.allCases.flatMap { priority in input.filter(priority.contains) }
        #expect(ordered.map(\.id) == ["question", "approval", "running", "done"])
        #expect(Set(ordered.map(\.id)).count == input.count)
    }

    @Test func everyNativePhaseHasExactlyOneVisiblePriority() {
        for phase in SessionPhase.allCases {
            let item = session(phase.rawValue, phase: phase)
            #expect(IslandSessionPriority.allCases.filter { $0.contains(item) }.count == 1)
        }
    }

    @Test func sharedWorkspaceDoesNotReplaceConversationTitles() {
        let one = IslandSessionRow(session: session("one", phase: .waitingForAnswer), referenceDate: .now, onJump: {})
        let two = IslandSessionRow(session: session("two", phase: .waitingForAnswer), referenceDate: .now, onJump: {})
        #expect(one.summaryHeadlineText != two.summaryHeadlineText)
        #expect(one.summaryHeadlineText == "同じワークスペース内の会話 one")
    }

    @Test func approvalCardNeverInventsStandingRulesOrModeChanges() {
        var request = PermissionRequest(title: "実行の許可", summary: "echo test", affectedPath: "/project",
            primaryActionTitle: "今回だけ許可", secondaryActionTitle: "拒否", toolName: "Bash")
        let empty = IslandSessionRow(session: session("empty", phase: .waitingForApproval, request: request),
            referenceDate: .now, onJump: {})
        #expect(empty.suggestedApprovalUpdates.isEmpty)
        let offered = ClaudePermissionUpdate.addRules(destination: .session,
            rules: [ClaudePermissionRuleValue(toolName: "Bash", ruleContent: "echo test")], behavior: .allow)
        request.suggestedUpdates = [offered]
        let supplied = IslandSessionRow(session: session("offered", phase: .waitingForApproval, request: request),
            referenceDate: .now, onJump: {})
        #expect(supplied.suggestedApprovalUpdates == [offered])
    }

    @Test func settingsPreviewUsesRealDecisionStateAndConversationIdentity() {
        let fixture = SessionListPreviewFixture(group: .none, sort: .lastUpdate, doneAge: "1m", lang: .shared)
        let sessions = fixture.sections.flatMap(\.items).map(\.previewSession)
        #expect(sessions.first(where: { $0.phase == .waitingForAnswer })?.questionPrompt != nil)
        #expect(sessions.first(where: { $0.phase == .waitingForApproval })?.permissionRequest?.suggestedUpdates.isEmpty == true)
        #expect(sessions.allSatisfy { !$0.title.isEmpty && $0.jumpTarget?.workspaceName.isEmpty == false })
    }
    @Test func unsupportedPaseoQuestionsOnlyHandOffToTheExactConversation() {
        let empty = QuestionPrompt(title: "Provider description", questions: [])
        let unsupported = StructuredQuestionPromptView(prompt: empty, isPaseo: true, onAnswer: { _ in
            Issue.record("Unsupported questions must not submit an answer")
        })
        #expect(unsupported.requiresPaseoQuestionHandoff)
        let supported = StructuredQuestionPromptView(prompt: QuestionPrompt(title: "Choose", questions: [
            QuestionPromptItem(question: "Choose", header: "Choice", options: [QuestionOption(label: "One")])
        ]), isPaseo: true, onAnswer: { _ in })
        #expect(!supported.requiresPaseoQuestionHandoff)
        let legacyFreeform = StructuredQuestionPromptView(prompt: empty, onAnswer: { _ in })
        #expect(!legacyFreeform.requiresPaseoQuestionHandoff)
    }

    @Test func forwardedQuestionKeepsParentIdentityAndNamesTheChildJump() {
        let parent = session("parent", phase: .waitingForAnswer)
        let own = IslandSessionRow(session: parent, referenceDate: .now, onJump: {})
        let child = IslandSessionRow(session: parent, referenceDate: .now,
            forwardedQuestionSourceTitle: "Child conversation", onJump: {})
        #expect(child.summaryHeadlineText == own.summaryHeadlineText)
        #expect(child.session.jumpTarget?.workspaceName == own.session.jumpTarget?.workspaceName)
        #expect(child.questionConversationActionTitle == LanguageManager.shared.t("decision.paseo.forwardedOpen"))
        #expect(own.questionConversationActionTitle == LanguageManager.shared.t("decision.paseo.open"))
        let blank = IslandSessionRow(session: parent, referenceDate: .now,
            forwardedQuestionSourceTitle: "  ", onJump: {})
        #expect(blank.questionConversationActionTitle == own.questionConversationActionTitle)
    }

}
