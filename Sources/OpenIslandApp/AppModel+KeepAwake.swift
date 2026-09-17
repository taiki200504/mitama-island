import Foundation
import OpenIslandCore

extension AppModel {
    /// Re-decides the sleep hold whenever running sessions change, and once a
    /// minute for the power source — plugging in and out has no notification
    /// cheap enough to be worth wiring.
    func configureKeepAwake() {
        trackKeepAwake()
        keepAwakeTimer.invalidate()
        keepAwakeTimer.timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshKeepAwake() }
        }
    }

    func refreshKeepAwake() {
        power.refresh()
        keepAwake.apply(KeepAwakePolicy.decide(
            enabled: settings.behaviour.keepsAwakeWhileRunning,
            runningCount: liveRunningCount,
            conditions: power.conditions
        ))
    }

    private func trackKeepAwake() {
        withObservationTracking {
            _ = liveRunningCount
            _ = settings.behaviour.keepsAwakeWhileRunning
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackKeepAwake() }
        }
        refreshKeepAwake()
    }
}
