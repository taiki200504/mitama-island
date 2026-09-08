import Foundation
import Observation

/// The unlock greeting: a ring resolving into a check and your name on the
/// closed island right after the screen unlocks.
///
/// A presentation, not a security check — nothing here authenticates anyone;
/// macOS has already unlocked the screen by the time any of it runs.
final class LockScanSettings: PreferenceGroup {
    let registrar = ObservationRegistrar()
    let store: PreferenceStore

    init(store: PreferenceStore = .standard) {
        self.store = store
    }

    var enabled: Bool {
        get { read(\.enabled, Keys.enabled, true) }
        set { write(\.enabled, Keys.enabled, newValue) }
    }

    /// Opens the camera for up to two seconds right after unlock to see
    /// whether a face is actually there, swapping the check glyph for a face
    /// glyph when one is found early enough.
    ///
    /// Off by default, like every other switch in this app that can open the
    /// camera outside a keypress: this one opens it on its own, not because
    /// anyone pressed anything.
    var usesCamera: Bool {
        get { read(\.usesCamera, Keys.usesCamera, false) }
        set { write(\.usesCamera, Keys.usesCamera, newValue) }
    }
}

extension LockScanSettings {
    enum Keys {
        static let enabled = "lockScan.enabled"
        static let usesCamera = "lockScan.usesCamera"
    }
}
