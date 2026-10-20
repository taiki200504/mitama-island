import Foundation
import OpenIslandCore

extension AppModel {
    func configureKeepAwake() {
        lidSleep.onFailure = { [weak self] in
            guard let self else { return }
            present(notice: lang.t("keepAwake.restoreFailed"))
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if !(await lidSleep.recover()) {
                settings.behaviour.manualKeepAwakeMode = .off
            }
            trackKeepAwake()
            resumeKeepAwakePolling()
        }
    }

    func resumeKeepAwakePolling() {
        keepAwakeTimer.invalidate()
        // Also bounds the delay when unplugging with the lid closed.
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshKeepAwake() }
        }
        keepAwakeTimer.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func setManualKeepAwake(_ mode: ManualKeepAwakePolicy.Mode) {
        if mode == .alwaysOn {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await lidSleep.preparePermission()
                activateManualKeepAwake(mode)
            }
        } else {
            activateManualKeepAwake(mode)
        }
    }

    private func activateManualKeepAwake(_ mode: ManualKeepAwakePolicy.Mode) {
        alwaysOnSuspended = false
        settings.behaviour.manualKeepAwakeStartedAt = Date().timeIntervalSince1970
        settings.behaviour.manualKeepAwakeMode = mode
        refreshKeepAwake()
        if mode == .off {
            Task { @MainActor in _ = await lidSleep.shutdown() }
        }
    }

    var manualKeepAwakeLabel: String {
        let behaviour = settings.behaviour
        let mode = behaviour.manualKeepAwakeMode
        if let duration = mode.duration {
            let remaining = max(0, behaviour.manualKeepAwakeStartedAt + duration - Date().timeIntervalSince1970)
            let minutes = remaining.isFinite ? min(480, ceil(remaining / 60)) : 0
            return lang.t("keepAwake.remaining", Int(minutes))
        }
        return lang.t(mode == .alwaysOn ? "keepAwake.alwaysOn.short" : mode.labelKey)
    }

    func refreshKeepAwake() {
        guard !isStoppingKeepAwake else { return }
        power.refresh()
        let behaviour = settings.behaviour
        let manual = ManualKeepAwakePolicy.decide(
            mode: behaviour.manualKeepAwakeMode, now: Date(),
            startedAt: Date(timeIntervalSince1970: behaviour.manualKeepAwakeStartedAt),
            conditions: power.conditions, runningCount: liveRunningCount,
            displayToo: behaviour.keepAwakeDisplay, wasSuspended: alwaysOnSuspended
        )
        var manualHold = false
        var displayToo = false
        switch manual {
        case .hold(let display):
            manualHold = true
            displayToo = display
            if behaviour.manualKeepAwakeMode == .alwaysOn && alwaysOnSuspended {
                present(notice: lang.t("keepAwake.alwaysOn.resumed"))
            }
            alwaysOnSuspended = false
        case .release(let reason):
            if behaviour.manualKeepAwakeMode == .alwaysOn {
                if !alwaysOnSuspended {
                    present(notice: lang.t("keepAwake.alwaysOn.paused"))
                }
                alwaysOnSuspended = true
            } else if behaviour.manualKeepAwakeMode != .off {
                behaviour.manualKeepAwakeMode = .off
                if reason.isSafetyRelease { present(notice: lang.t("keepAwake.release.\(reason.rawValue)")) }
            }
        }
        let automatic = KeepAwakePolicy.decide(
            enabled: behaviour.keepsAwakeWhileRunning,
            runningCount: liveRunningCount, conditions: power.conditions
        )
        let suspended = behaviour.manualKeepAwakeMode == .alwaysOn && alwaysOnSuspended
        keepAwake.apply(suspended ? .release(.disabled) : (manualHold ? .hold : automatic), displayToo: displayToo)
        lidSleep.setEnabled(manualHold && (behaviour.manualKeepAwakeMode == .alwaysOn
                            || (behaviour.keepAwakeClosedLid && power.isOnAC)))
    }

    private func trackKeepAwake() {
        withObservationTracking {
            _ = liveRunningCount
            _ = settings.behaviour.keepsAwakeWhileRunning
            _ = settings.behaviour.manualKeepAwakeMode
            _ = settings.behaviour.manualKeepAwakeStartedAt
            _ = settings.behaviour.keepAwakeDisplay
            _ = settings.behaviour.keepAwakeClosedLid
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackKeepAwake() }
        }
        refreshKeepAwake()
    }
}
