import Foundation
import Observation

/// Whether the eye-break loop runs on its own, whether the timer makes
/// noise, and whether it moves into its next phase by itself.
final class TimerSettings: PreferenceGroup {
    let registrar = ObservationRegistrar()
    let store: PreferenceStore

    init(store: PreferenceStore = .standard) {
        self.store = store
    }

    /// Runs the 20-work/20-rest loop from launch and keeps it running across
    /// every cycle. Off by default: an eye-break timer that starts itself
    /// without being asked is a surprise the first time it interrupts you.
    var eyeBreakEnabled: Bool {
        get { read(\.eyeBreakEnabled, Keys.eyeBreakEnabled, false) }
        set { write(\.eyeBreakEnabled, Keys.eyeBreakEnabled, newValue) }
    }

    /// Whether a finished phase plays `NotificationSoundEvent.timerFinished`.
    var playsSound: Bool {
        get { read(\.playsSound, Keys.playsSound, true) }
        set { write(\.playsSound, Keys.playsSound, newValue) }
    }

    /// Whether a Pomodoro or an eye-break moves into its next phase on its
    /// own once the current one ends. Off leaves the timer sitting on
    /// `.finished` until the opened surface's own controls advance it.
    var autoAdvance: Bool {
        get { read(\.autoAdvance, Keys.autoAdvance, true) }
        set { write(\.autoAdvance, Keys.autoAdvance, newValue) }
    }
}

extension TimerSettings {
    enum Keys {
        static let eyeBreakEnabled = "timer.eyeBreakEnabled"
        static let playsSound = "timer.playsSound"
        static let autoAdvance = "timer.autoAdvance"
    }
}
