import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// Answering on the user's behalf is the one thing the island does that they
/// cannot take back, so each of these pins down a way it must not misfire.
@MainActor
struct AutoResponseRuleTests {
    private func makeModel() -> AppModel {
        let name = "auto-response-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return AppModel(settings: SettingsStore(store: PreferenceStore(suite: suite)))
    }

    private func session(
        id: String = "s1",
        directory: String = "/tmp/auto-approved",
        tool: AgentTool = .claudeCode
    ) -> AgentSession {
        var session = AgentSession(
            id: id,
            title: "Claude · demo",
            tool: tool,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "running",
            updatedAt: Date(),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "demo",
                paneTitle: "claude",
                workingDirectory: directory,
                terminalSessionID: id
            )
        )
        session.isProcessAlive = true
        return session
    }

    private func requestPermission(_ model: AppModel, sessionID: String = "s1") {
        model.applyTrackedEvent(
            .permissionRequested(
                PermissionRequested(
                    sessionID: sessionID,
                    request: PermissionRequest(
                        title: "Run",
                        summary: "rm -rf build",
                        affectedPath: "/tmp/auto-approved",
                        toolName: "Bash"
                    ),
                    timestamp: Date()
                )
            ),
            updateLastActionMessage: false,
            ingress: .bridge
        )
    }

    private func rule(
        _ behavior: AutoResponseBehavior,
        pattern: String = "/tmp/auto-approved"
    ) -> AutoResponseRule {
        AutoResponseRule(field: .workingDirectory, match: .equals, pattern: pattern, behavior: behavior)
    }

    @Test
    func aMatchingRuleAnswersWithoutShowingACard() {
        let model = makeModel()
        model.state = SessionState(sessions: [session()])
        model.settings.autoResponse.addRule(rule(.allowOnce))

        requestPermission(model)

        #expect(model.state.session(id: "s1")?.phase != .waitingForApproval)
        #expect(model.pendingApprovalSessions.isEmpty)
    }

    /// Without a rule the request has to reach the user untouched.
    @Test
    func anUnmatchedRequestStillWaits() {
        let model = makeModel()
        model.state = SessionState(sessions: [session()])
        model.settings.autoResponse.addRule(rule(.allowOnce, pattern: "/tmp/somewhere-else"))

        requestPermission(model)

        #expect(model.state.session(id: "s1")?.phase == .waitingForApproval)
    }

    /// The one switch that has to work when a rule turns out to be wrong.
    @Test
    func theMasterSwitchStopsEveryRule() {
        let model = makeModel()
        model.state = SessionState(sessions: [session()])
        model.settings.autoResponse.addRule(rule(.bypassPermissions))
        model.settings.autoResponse.isEnabled = false

        requestPermission(model)

        #expect(model.state.session(id: "s1")?.phase == .waitingForApproval)
    }

    /// A rule firing on something the island never displayed is a decision made
    /// entirely out of sight, so hidden sessions are left for the terminal.
    @Test
    func silencedSessionsAreNotAnsweredBehindTheUsersBack() {
        let model = makeModel()
        model.state = SessionState(sessions: [session()])
        model.settings.autoResponse.addRule(rule(.bypassPermissions))
        model.settings.notificationFilters.addRule(
            SilenceRule(field: .workingDirectory, match: .equals, pattern: "/tmp/auto-approved")
        )

        requestPermission(model)

        #expect(model.state.session(id: "s1")?.phase == .waitingForApproval)
    }

    /// Nothing about a standing rule can be a refusal — denying is a judgement
    /// about the specific thing that was asked.
    @Test
    func noBehaviourDenies() {
        #expect(AutoResponseBehavior.allCases.map(\.rawValue) == ["allowOnce", "acceptEdits", "bypassPermissions"])
    }

    /// Right-clicking the same folder twice should not leave two rules to delete.
    @Test
    func duplicateRulesAreRejected() {
        let model = makeModel()
        model.autoAnswerSessions(matching: rule(.allowOnce))
        model.autoAnswerSessions(matching: rule(.bypassPermissions))

        #expect(model.settings.autoResponse.rules.count == 1)
    }

    @Test
    func anEmptyPatternIsNotARule() {
        let model = makeModel()
        model.autoAnswerSessions(matching: rule(.allowOnce, pattern: "   "))

        #expect(model.settings.autoResponse.rules.isEmpty)
    }

    /// Rules survive a relaunch — a rule that has to be written again every
    /// morning is worse than no rule at all.
    @Test
    func rulesPersist() {
        let name = "auto-response-persist-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)

        AutoResponseSettings(store: PreferenceStore(suite: suite)).addRule(rule(.acceptEdits))
        let reopened = AutoResponseSettings(store: PreferenceStore(suite: suite))

        #expect(reopened.rules.map(\.behavior) == [.acceptEdits])
    }
}
