import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// The four settings that decide whether the island is on screen at all.
@MainActor
struct IslandVisibilityTests {
    private func makeModel() -> (AppModel, SettingsStore) {
        let name = "visibility-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        let settings = SettingsStore(store: PreferenceStore(suite: suite))
        return (isolatedAppModel(settings: settings), settings)
    }

    private func liveSession(id: String = "s") -> AgentSession {
        var session = AgentSession(
            id: id,
            title: "Claude · demo",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Running",
            updatedAt: Date(),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "demo",
                paneTitle: "claude",
                workingDirectory: "/tmp/demo",
                terminalSessionID: "g1"
            )
        )
        session.isProcessAlive = true
        return session
    }

    @Test
    func manualOnlyPersistsAndDefaultsOff() {
        let (_, settings) = makeModel()
        #expect(!settings.behaviour.manualOnly)
        settings.behaviour.manualOnly = true
        #expect(BehaviourSettings(store: settings.behaviour.store).manualOnly)
        settings.behaviour.manualOnly = false
        #expect(!BehaviourSettings(store: settings.behaviour.store).manualOnly)
    }

    @Test
    func manualOnlyHidesClosedPillAndRestoresItWhenDisabled() {
        let (model, settings) = makeModel()
        settings.behaviour.manualOnly = true
        #expect(!model.islandMayBeVisible)
        model.state = SessionState(sessions: [liveSession()])
        #expect(!model.islandMayBeVisible)
        model.overlay.notchStatus = .opened
        #expect(model.islandMayBeVisible)
        model.overlay.notchStatus = .closed
        #expect(!model.islandMayBeVisible)
        settings.behaviour.manualOnly = false
        #expect(model.islandMayBeVisible)
    }

    @Test
    func manualOnlyKeepsActionableRequestsAndSuppressesOrdinaryUpdates() {
        let (model, settings) = makeModel()
        settings.behaviour.manualOnly = true
        settings.sound.isMuted = true
        model.disablesOverlayEventMonitoringDuringHarness = true
        defer { model.notchClose() }
        for phase in [SessionPhase.waitingForApproval, .waitingForAnswer, .running, .completed] {
            var session = liveSession()
            session.phase = phase
            model.state = SessionState(sessions: [session])
            model.notchOpen(reason: .notification, surface: .sessionList(actionableSessionID: session.id))
            let actionable = phase == .waitingForApproval || phase == .waitingForAnswer
            #expect((model.notchStatus == .opened) == actionable)
            model.notchClose()
            #expect(!model.islandMayBeVisible)
        }
    }

    @Test
    func hiddenPillDoesNotCaptureTopBarClicks() {
        let (model, settings) = makeModel()
        settings.behaviour.manualOnly = true
        let controller = OverlayPanelController()
        controller.model = model
        #expect(!controller.isPointInClosedSurfaceArea(.zero))
    }

    @Test
    func manualOnlyExplicitToggleOpensAndCloses() {
        let (_, settings) = makeModel()
        settings.behaviour.manualOnly = true
        settings.sound.isMuted = true
        let overlay = OverlayUICoordinator(settings: settings)
        overlay.toggleOverlay()
        #expect(overlay.notchStatus == .opened)
        #expect(overlay.islandMayBeVisible)
        overlay.toggleOverlay()
        #expect(overlay.notchStatus == .closed)
        #expect(!overlay.islandMayBeVisible)
        overlay.notchOpen(reason: .click)
        #expect(overlay.islandMayBeVisible)
        overlay.notchClose()
        #expect(!overlay.islandMayBeVisible)
    }

    @Test
    func manualOnlyRejectsAutomaticOpensAndPop() {
        let (model, settings) = makeModel()
        settings.behaviour.manualOnly = true
        for reason in [NotchOpenReason.hover, .boot, .handGesture, .notification] {
            model.overlay.notchOpen(reason: reason)
            #expect(model.notchStatus == .closed)
        }
        model.overlay.notchPop()
        #expect(model.notchStatus == .closed)
    }

    // MARK: Smart suppression

    /// This behaviour already existed under the name
    /// `suppressFrontmostNotifications`. The two names must be one setting, or
    /// the general pane would edit a copy nothing reads.
    @Test
    func smartSuppressionIsTheSameSettingAsTheOlderName() {
        let (model, settings) = makeModel()

        #expect(model.suppressFrontmostNotifications)
        #expect(settings.behaviour.smartSuppression)

        settings.behaviour.smartSuppression = false
        #expect(!model.suppressFrontmostNotifications)

        model.suppressFrontmostNotifications = true
        #expect(settings.behaviour.smartSuppression)
    }

    /// Anyone who already had this switched off must keep it off after the
    /// rename, so the stored key cannot change.
    @Test
    func theExistingStoredKeyIsStillTheOneUsed() {
        #expect(BehaviourSettings.Keys.smartSuppression == "app.suppressFrontmostNotifications")
    }

    // MARK: Idle hiding

    @Test
    func theIslandStaysVisibleWhileSomethingIsRunning() {
        let (model, settings) = makeModel()
        settings.behaviour.autoHideWhenIdle = true
        model.state = SessionState(sessions: [liveSession()])

        #expect(model.islandMayBeVisible)
    }

    @Test
    func theIslandHidesWhenNothingIsRunningAndAskedTo() {
        let (model, settings) = makeModel()
        settings.behaviour.autoHideWhenIdle = true
        model.state = SessionState(sessions: [])

        #expect(!model.islandMayBeVisible)
    }

    /// Off by default, so nobody's island disappears after an update.
    @Test
    func idleHidingIsOffUntilAskedFor() {
        let (model, settings) = makeModel()
        #expect(!settings.behaviour.autoHideWhenIdle)

        model.state = SessionState(sessions: [])
        #expect(model.islandMayBeVisible)
    }

    /// A session hidden by a notification filter is not a reason to keep the
    /// island on screen.
    @Test
    func aFilteredOutSessionDoesNotCountAsRunning() {
        let (model, settings) = makeModel()
        settings.behaviour.autoHideWhenIdle = true
        settings.notificationFilters.addRule(
            SilenceRule(field: .workingDirectory, match: .contains, pattern: "/tmp/demo")
        )
        model.state = SessionState(sessions: [liveSession()])

        #expect(!model.islandMayBeVisible)
    }

    // MARK: Outside click

    @Test
    func outsideClickDismissalIsOnByDefault() {
        let (_, settings) = makeModel()
        #expect(settings.behaviour.dismissOnOutsideClick)
    }

    @Test
    func outsideClickDismissalCanBeTurnedOff() {
        let (_, settings) = makeModel()
        settings.behaviour.dismissOnOutsideClick = false
        #expect(!settings.behaviour.dismissOnOutsideClick)
    }

    // MARK: The ledger

    /// These four stopped being promises in this change.
    @Test
    func theFourVisibilityCapabilitiesAreLive() {
        #expect(PendingCapability.foregroundTerminalDetection.isImplemented)
        #expect(PendingCapability.outsideClickDetection.isImplemented)
        #expect(PendingCapability.fullscreenDetection.isImplemented)
        #expect(PendingCapability.autoHideTimer.isImplemented)
    }
}
