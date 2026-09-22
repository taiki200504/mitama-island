import Foundation
import Observation

/// The opt-in control for the standing microphone ("earshot").
///
/// This is deliberately a second, separate switch from `VoiceCommandSettings`.
/// Answering a card by voice opens the microphone for eight seconds after a
/// keypress; this keeps it open all day. Those are different bargains and the
/// person should be able to take one without the other.
///
/// Off by default, and it stays off until someone turns it on in Settings.
/// While it is on, macOS shows the orange microphone indicator for as long as
/// the app is listening — that is the honest cost of this feature, not a bug.
final class AmbientListenSettings: PreferenceGroup {
    let registrar = ObservationRegistrar()
    let store: PreferenceStore

    init(store: PreferenceStore = .standard) {
        self.store = store
    }

    var isEnabled: Bool {
        get { read(\.isEnabled, Keys.enabled, false) }
        set { write(\.isEnabled, Keys.enabled, newValue) }
    }

    /// How much silence closes the current recording. Matches the batch's
    /// episode rule (90 seconds always splits), so the file boundary and the
    /// episode boundary agree and the batch has less to stitch back together.
    var silenceToCloseSeconds: Double {
        get { read(\.silenceToCloseSeconds, Keys.silenceToClose, Defaults.silenceToCloseSeconds) }
        set { write(\.silenceToCloseSeconds, Keys.silenceToClose, Self.clampSilence(newValue)) }
    }

    /// A hard cap on one file, so a long meeting does not become one giant WAV.
    var maximumMinutes: Double {
        get { read(\.maximumMinutes, Keys.maximumMinutes, Defaults.maximumMinutes) }
        set { write(\.maximumMinutes, Keys.maximumMinutes, Self.clampMaximum(newValue)) }
    }

    /// Pause while a call app is running. On by default: the other side of a
    /// call has not agreed to any of this, and their consent is not ours to give.
    var pauseDuringCalls: Bool {
        get { read(\.pauseDuringCalls, Keys.pauseDuringCalls, true) }
        set { write(\.pauseDuringCalls, Keys.pauseDuringCalls, newValue) }
    }

    private static func clampSilence(_ seconds: Double) -> Double {
        min(max(seconds, Defaults.minimumSilenceSeconds), Defaults.maximumSilenceSeconds)
    }

    private static func clampMaximum(_ minutes: Double) -> Double {
        min(max(minutes, Defaults.minimumMinutes), Defaults.maximumMinutesCap)
    }
}

extension AmbientListenSettings {
    enum Defaults {
        static let silenceToCloseSeconds: Double = 90.0
        static let minimumSilenceSeconds: Double = 10.0
        static let maximumSilenceSeconds: Double = 300.0
        static let maximumMinutes: Double = 20.0
        static let minimumMinutes: Double = 1.0
        static let maximumMinutesCap: Double = 60.0
    }

    enum Keys {
        static let enabled = "ambientListen.enabled"
        static let silenceToClose = "ambientListen.silenceToCloseSeconds"
        static let maximumMinutes = "ambientListen.maximumMinutes"
        static let pauseDuringCalls = "ambientListen.pauseDuringCalls"
    }
}
