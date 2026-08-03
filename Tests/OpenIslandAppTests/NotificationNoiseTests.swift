import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// What the island is allowed to interrupt for, and what it refuses to throw away.
@MainActor
struct NotificationNoiseTests {
    private func makeModel() -> (AppModel, SettingsStore) {
        let name = "noise-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        let settings = SettingsStore(store: PreferenceStore(suite: suite))
        return (AppModel(settings: settings), settings)
    }

    private func session(id: String, phase: SessionPhase) -> AgentSession {
        var session = AgentSession(
            id: id,
            title: "Claude · demo",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: phase,
            summary: "s",
            updatedAt: Date(),
            jumpTarget: JumpTarget(
                terminalApp: "Cursor",
                workspaceName: "demo",
                paneTitle: "claude",
                workingDirectory: "/tmp/demo",
                terminalSessionID: "c1"
            )
        )
        session.isProcessAlive = true
        return session
    }

    /// Clicking back into the terminal to read a diff must not throw away the
    /// request that is blocking the agent.
    @Test
    func aCardWaitingOnTheUserSurvivesAnOutsideClick() {
        let (model, _) = makeModel()
        model.state = SessionState(sessions: [session(id: "a", phase: .waitingForApproval)])
        model.overlay.islandSurface = .sessionList(actionableSessionID: "a")

        #expect(model.islandSurfaceAwaitsUserAction)
    }

    @Test
    func aQuestionAlsoCountsAsWaitingOnTheUser() {
        let (model, _) = makeModel()
        model.state = SessionState(sessions: [session(id: "a", phase: .waitingForAnswer)])
        model.overlay.islandSurface = .sessionList(actionableSessionID: "a")

        #expect(model.islandSurfaceAwaitsUserAction)
    }

    /// A finished session has nothing pending, so dismissing it is harmless.
    @Test
    func aFinishedSessionDoesNotBlockDismissal() {
        let (model, _) = makeModel()
        model.state = SessionState(sessions: [session(id: "a", phase: .completed)])
        model.overlay.islandSurface = .sessionList(actionableSessionID: "a")

        #expect(!model.islandSurfaceAwaitsUserAction)
    }

    @Test
    func theSessionListItselfNeverBlocksDismissal() {
        let (model, _) = makeModel()
        model.overlay.islandSurface = .sessionList()

        #expect(!model.islandSurfaceAwaitsUserAction)
    }

    /// The agents' own bookkeeping sessions are hidden unless asked for.
    @Test
    func theBuiltInFiltersStartOn() {
        let (_, settings) = makeModel()

        for preset in SilenceRule.presets {
            #expect(settings.notificationFilters.isEnabled(preset), "\(preset.id) should start on")
        }
    }

    @Test
    func aBuiltInFilterCanStillBeSwitchedOff() {
        let (_, settings) = makeModel()
        let preset = SilenceRule.presets[0]

        settings.notificationFilters.setEnabled(false, for: preset)
        #expect(!settings.notificationFilters.isEnabled(preset))
    }

    /// This switch shipped without anything reading it.
    @Test
    func theCompletionSwitchDefaultsOnAndIsStored() {
        let (_, settings) = makeModel()
        #expect(settings.behaviour.expandOnCompletion)

        settings.behaviour.expandOnCompletion = false
        #expect(!settings.behaviour.expandOnCompletion)
    }
}
