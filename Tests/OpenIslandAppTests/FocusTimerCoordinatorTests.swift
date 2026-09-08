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

    @Test("A finished countdown plays the finish sound and posts a timerDone sneak peek")
    func finishPlaysSoundAndPeeks() async throws {
        let coordinator = makeCoordinator()
        var cues: [String] = []
        NotificationSoundService.harnessSink = { cues.append($0) }
        defer { NotificationSoundService.harnessSink = nil }

        let overlay = OverlayUICoordinator()
        coordinator.overlay = overlay

        coordinator.start(.countdown(0.05))

        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while overlay.sneakPeek == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(overlay.sneakPeek?.kind == .timerDone)
        #expect(cues.contains { $0.hasPrefix("sound.cue=") })
    }
}
