import Foundation
import Observation

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
    }
}
