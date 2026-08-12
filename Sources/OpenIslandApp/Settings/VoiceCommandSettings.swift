import Foundation
import Observation

/// The opt-in controls for answering a waiting card by voice.
///
/// The microphone stays shut until this is on, and even then only opens for the
/// few seconds after the key is pressed — and only when something is actually
/// waiting to be answered.
final class VoiceCommandSettings: PreferenceGroup {
    let registrar = ObservationRegistrar()
    let store: PreferenceStore

    init(store: PreferenceStore = .standard) {
        self.store = store
    }

    var isEnabled: Bool {
        get { read(\.isEnabled, Keys.enabled, false) }
        set { write(\.isEnabled, Keys.enabled, newValue) }
    }

    /// How long to listen. Long enough for "二番でお願いします", short enough
    /// that a mistaken press does not leave the microphone open.
    var windowSeconds: Double {
        get { read(\.windowSeconds, Keys.windowSeconds, Defaults.windowSeconds) }
        set { write(\.windowSeconds, Keys.windowSeconds, Self.clampWindowSeconds(newValue)) }
    }

    /// BCP-47. Recognition is on-device and per-locale, so this decides which
    /// model has to be installed.
    var localeIdentifier: String {
        get { read(\.localeIdentifier, Keys.localeIdentifier, Defaults.localeIdentifier) }
        set { write(\.localeIdentifier, Keys.localeIdentifier, newValue) }
    }

    var locale: Locale { Locale(identifier: localeIdentifier) }

    private static func clampWindowSeconds(_ seconds: Double) -> Double {
        min(max(seconds, Defaults.minimumWindowSeconds), Defaults.maximumWindowSeconds)
    }
}

extension VoiceCommandSettings {
    enum Defaults {
        static let windowSeconds: Double = 8.0
        static let minimumWindowSeconds: Double = 2.0
        static let maximumWindowSeconds: Double = 20.0
        static let localeIdentifier = "ja-JP"
    }

    enum Keys {
        static let enabled = "voiceCommand.enabled"
        static let windowSeconds = "voiceCommand.windowSeconds"
        static let localeIdentifier = "voiceCommand.locale"
    }
}
