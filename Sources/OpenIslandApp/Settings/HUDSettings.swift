import CoreFoundation
import Foundation
import Observation

/// Whether volume, brightness, and keyboard-backlight keys are answered by
/// the island's own gauge instead of macOS's built-in on-screen display.
///
/// `replacesSystem` is the master switch: everything else here only matters
/// once it is on, and turning it on is also the one place that asks for
/// Accessibility — see `DisplaySettingsPane`'s System HUD section.
final class HUDSettings: PreferenceGroup {
    let registrar = ObservationRegistrar()
    let store: PreferenceStore

    init(store: PreferenceStore = .standard) {
        self.store = store
    }

    /// Off by default: this is the one switch in this group that changes
    /// what macOS itself does with a keypress the moment it is on, and it
    /// needs a permission dialog to get there.
    var replacesSystem: Bool {
        get { read(\.replacesSystem, Keys.replacesSystem, false) }
        set { write(\.replacesSystem, Keys.replacesSystem, newValue) }
    }

    var volume: Bool {
        get { read(\.volume, Keys.volume, true) }
        set { write(\.volume, Keys.volume, newValue) }
    }

    var brightness: Bool {
        get { read(\.brightness, Keys.brightness, true) }
        set { write(\.brightness, Keys.brightness, newValue) }
    }

    /// Off by default, like `LockScanSettings.usesCamera`: of the three
    /// meters this one is the most likely to shift between macOS versions,
    /// so it stays opt-in even once `replacesSystem` is on.
    var keyboardBacklight: Bool {
        get { read(\.keyboardBacklight, Keys.keyboardBacklight, false) }
        set { write(\.keyboardBacklight, Keys.keyboardBacklight, newValue) }
    }

    /// Follows macOS's own "Play feedback when volume is changed" setting
    /// until this is switched explicitly, at which point the stored value
    /// wins — see `systemFeedbackSoundDefault`.
    var playsFeedbackSound: Bool {
        get { read(\.playsFeedbackSound, Keys.playsFeedbackSound, Self.systemFeedbackSoundDefault) }
        set { write(\.playsFeedbackSound, Keys.playsFeedbackSound, newValue) }
    }

    private static var systemFeedbackSoundDefault: Bool {
        guard let value = CFPreferencesCopyAppValue(
            "com.apple.sound.beep.feedback" as CFString,
            kCFPreferencesAnyApplication
        ) as? NSNumber else {
            return true
        }
        return value.boolValue
    }
}

extension HUDSettings {
    enum Keys {
        static let replacesSystem = "hud.replacesSystem"
        static let volume = "hud.volume"
        static let brightness = "hud.brightness"
        static let keyboardBacklight = "hud.keyboardBacklight"
        static let playsFeedbackSound = "hud.playsFeedbackSound"
    }
}
