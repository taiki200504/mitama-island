import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// Proves the general pane's switches actually reach the engine.
///
/// A settings toggle that stores a value but changes nothing is the failure mode
/// this whole surface is built to avoid, so each wired-up control gets a test
/// that fails if the connection is cut.
@MainActor
struct GeneralBehaviourWiringTests {
    /// Records every jump the model actually attempts.
    private final class JumpLog: @unchecked Sendable {
        private let lock = NSLock()
        private var targets: [JumpTarget] = []

        func record(_ target: JumpTarget) {
            lock.lock(); defer { lock.unlock() }
            targets.append(target)
        }

        var count: Int {
            lock.lock(); defer { lock.unlock() }
            return targets.count
        }
    }

    private func makeModel() -> (AppModel, SettingsStore, JumpLog) {
        let name = "wiring-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        let settings = SettingsStore(store: PreferenceStore(suite: suite))
        let log = JumpLog()
        let model = AppModel(
            terminalJumpAction: { target in
                log.record(target)
                return "jumped"
            },
            settings: settings
        )
        return (model, settings, log)
    }

    /// The jump runs on a detached task, so give it a moment to land.
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(200))
    }

    private func session(id: String = "s1", terminal: String = "Ghostty") -> AgentSession {
        AgentSession(
            id: id,
            title: "Claude · demo",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Running",
            updatedAt: Date(timeIntervalSince1970: 1_000),
            jumpTarget: JumpTarget(
                terminalApp: terminal,
                workspaceName: "demo",
                paneTitle: "claude ~/demo",
                workingDirectory: "/tmp/demo",
                terminalSessionID: "ghostty-1"
            )
        )
    }

    @Test
    func clickingASessionJumpsByDefault() async {
        let (model, settings, log) = makeModel()
        #expect(settings.behaviour.disableClickToJump == false)

        model.jumpToSession(session())
        await settle()

        #expect(log.count == 1)
    }

    @Test
    func disablingClickToJumpStopsTheRowTapFromJumping() async {
        let (model, settings, log) = makeModel()
        settings.behaviour.disableClickToJump = true

        model.jumpToSession(session())
        await settle()

        // `lastActionMessage` carries unrelated startup text, so the jump log is
        // the only reliable signal here.
        #expect(log.count == 0)
    }

    /// An unknown terminal still has to explain itself rather than do nothing,
    /// so the guard above must not swallow that path when jumping is enabled.
    @Test
    func unknownTerminalStillReportsWhyItCannotJump() async {
        let (model, _, log) = makeModel()

        model.jumpToSession(session(terminal: "unknown"))
        await settle()

        #expect(log.count == 0)
        #expect(model.lastActionMessage.localizedCaseInsensitiveContains("unknown"))
    }

    @Test
    func autoCollapseOnLeaveGatesThePointerExitPath() {
        let (model, settings, _) = makeModel()

        model.overlay.notchStatus = .opened
        model.overlay.notchOpenReason = .hover
        model.overlay.islandSurface = .sessionList()

        #expect(model.shouldAutoCollapseOnMouseLeave)

        settings.behaviour.autoCollapseOnLeave = false
        #expect(!model.shouldAutoCollapseOnMouseLeave)
    }

    /// This setting shipped hard-coded to `true` in the UI, so the regression to
    /// guard against is it quietly going back to being unconditional.
    @Test
    func autoCollapseOnLeaveDefaultsToOnButIsNotHardCoded() {
        let (_, settings, _) = makeModel()
        #expect(settings.behaviour.autoCollapseOnLeave == true)

        settings.behaviour.autoCollapseOnLeave = false
        #expect(settings.behaviour.autoCollapseOnLeave == false)
    }

    @Test
    func hoverDurationDefaultMatchesTheConstantTheAppShipped() {
        #expect(AppModel.hoverOpenDelay == BehaviourSettings.Defaults.hoverDuration)
    }

    /// Changing the default would shorten every existing user's auto-reveal
    /// without them asking, so it is pinned to the value the app already used.
    @Test
    func autoRevealDwellDefaultMatchesThePreviousFixedDelay() {
        let (_, settings, _) = makeModel()
        #expect(settings.behaviour.autoRevealDwell == 10)
        #expect(BehaviourSettings.Defaults.autoRevealDwellOptions.contains(10))
    }
}
