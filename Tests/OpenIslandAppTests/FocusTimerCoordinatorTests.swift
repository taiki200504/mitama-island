import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
@Suite("Focus timer coordinator")
struct FocusTimerCoordinatorTests {
    private func makeCoordinator() -> FocusTimerCoordinator {
        let name = "focus-timer-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        let store = PreferenceStore(suite: suite)
        let coordinator = FocusTimerCoordinator()
        coordinator.soundSettings = SoundSettings(store: store)
        coordinator.timerSettings = TimerSettings(store: store)
        return coordinator
    }

    @Test("start/pause/resume/reset drive the coordinator's own state")
    func startPauseResumeReset() {
        let coordinator = makeCoordinator()
        coordinator.start(.countdown(60))
        guard case .running = coordinator.state.phase else {
            Issue.record("expected running after start")
            return
        }

        coordinator.pause()
        guard case .paused = coordinator.state.phase else {
            Issue.record("expected paused after pause")
            return
        }

        coordinator.resume()
        guard case .running = coordinator.state.phase else {
            Issue.record("expected running again after resume")
            return
        }

        coordinator.reset()
        #expect(coordinator.state == .idle)
    }

    @Test("Loading a debug state sets it directly, with no run loop attached")
    func loadDebugStateSetsDirectly() {
        let coordinator = makeCoordinator()
        let state = FocusTimerReducer.reduce(.idle, .start(.countdown(600)), now: .now)
        coordinator.loadDebugState(state)
        #expect(coordinator.state == state)
    }

    @Test("A finished countdown requests its exact finish cue and posts a timerDone sneak peek")
    func finishPlaysSoundAndPeeks() {
        let coordinator = makeCoordinator()
        var events: [NotificationSoundEvent] = []
        coordinator.finishSoundPlayer = { event, _ in events.append(event) }
        coordinator.timerSettings.playsSound = true
        coordinator.timerSettings.autoAdvance = false
        let overlay = OverlayUICoordinator()
        coordinator.overlay = overlay

        // The same completion path used after sleep/wake, with an already
        // elapsed deadline. No task timing or shared audio sink is involved.
        let elapsed = FocusTimerReducer.reduce(.idle, .start(.countdown(60)),
            now: Date(timeIntervalSince1970: 0))
        coordinator.loadDebugState(elapsed)
        coordinator.recomputeAfterWake()

        #expect(overlay.sneakPeek?.kind == .timerDone)
        #expect(events == [.timerFinished])
        // Another wake must not announce the same completion twice.
        coordinator.recomputeAfterWake()
        #expect(events == [.timerFinished])
    }
}
