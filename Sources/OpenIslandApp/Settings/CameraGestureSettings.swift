import Foundation
import Observation
import OpenIslandCore

/// The opt-in controls for opening the island with a two-finger camera gesture.
///
/// Camera capture stays elsewhere: keeping these values inert until that layer
/// starts means people who leave the feature off are never asked for access.
final class CameraGestureSettings: PreferenceGroup {
    let registrar = ObservationRegistrar()
    let store: PreferenceStore

    init(store: PreferenceStore = .standard) {
        self.store = store
    }

    var isEnabled: Bool {
        get { read(\.isEnabled, Keys.enabled, false) }
        set { write(\.isEnabled, Keys.enabled, newValue) }
    }

    var windowSeconds: Double {
        get { read(\.windowSeconds, Keys.windowSeconds, Defaults.windowSeconds) }
        set { write(\.windowSeconds, Keys.windowSeconds, Self.clampWindowSeconds(newValue)) }
    }

    /// Holds the camera open while a card is waiting, so a raised hand starts
    /// the microphone instead of a keystroke.
    ///
    /// Off by default, and worth leaving off: this is the one path where the
    /// camera runs for longer than a keypress.
    var answersByPalm: Bool {
        get { read(\.answersByPalm, Keys.answersByPalm, false) }
        set { write(\.answersByPalm, Keys.answersByPalm, newValue) }
    }

    /// Keeps the camera open even when nothing is waiting, so a raised hand is
    /// a standing input rather than an answer to a question.
    ///
    /// Off by default and the most expensive switch here: macOS lights the
    /// camera indicator for as long as the device runs and no app can turn that
    /// off, so this is a green light all day. It only means anything alongside
    /// `answersByPalm`, and the power guard still closes it for a shut lid, a
    /// hot machine or a low battery.
    var staysOpen: Bool {
        get { read(\.staysOpen, Keys.staysOpen, false) }
        set { write(\.staysOpen, Keys.staysOpen, newValue) }
    }

    /// How hard a hand has to try. Stored raw so an unknown future value falls
    /// back to the middle setting rather than failing to decode.
    var sensitivityRawValue: String {
        get { read(\.sensitivityRawValue, Keys.sensitivity, GestureSensitivity.default.rawValue) }
        set { write(\.sensitivityRawValue, Keys.sensitivity, newValue) }
    }

    var sensitivity: GestureSensitivity {
        get { GestureSensitivity(rawValue: sensitivityRawValue) }
        set { sensitivityRawValue = newValue.rawValue }
    }

    private static func clampWindowSeconds(_ seconds: Double) -> Double {
        min(max(seconds, Defaults.minimumWindowSeconds), Defaults.maximumWindowSeconds)
    }
}

extension CameraGestureSettings {
    enum Defaults {
        static let windowSeconds: Double = 5.0
        static let minimumWindowSeconds: Double = 1.0
        static let maximumWindowSeconds: Double = 15.0
    }

    enum Keys {
        static let enabled = "cameraGesture.enabled"
        static let windowSeconds = "cameraGesture.windowSeconds"
        static let answersByPalm = "cameraGesture.answersByPalm"
        static let sensitivity = "cameraGesture.sensitivity"
        static let staysOpen = "cameraGesture.staysOpen"
    }
}
