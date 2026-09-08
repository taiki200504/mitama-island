import Foundation
import Observation

/// Whether the island keeps a clipboard history at all, whether it survives a
/// relaunch, and whether picking a row also pastes it.
final class ClipboardSettings: PreferenceGroup {
    let registrar = ObservationRegistrar()
    let store: PreferenceStore

    init(store: PreferenceStore = .standard) {
        self.store = store
    }

    /// Off by default: watching everything copied on the machine — including,
    /// however briefly, whatever a password manager forgets to tag — is not a
    /// thing to switch on without being asked.
    var enabled: Bool {
        get { read(\.enabled, Keys.enabled, false) }
        set { write(\.enabled, Keys.enabled, newValue) }
    }

    /// Off by default. Remembering copies across a relaunch is a stronger
    /// claim than remembering them for the current session alone — a session
    /// that never touched disk has nothing left over for a lost laptop.
    var persistsToDisk: Bool {
        get { read(\.persistsToDisk, Keys.persistsToDisk, false) }
        set { write(\.persistsToDisk, Keys.persistsToDisk, newValue) }
    }

    /// Off by default, and only ever effective with Accessibility granted —
    /// see `FeatureAvailability` on the settings row that exposes this.
    var pastesOnSelect: Bool {
        get { read(\.pastesOnSelect, Keys.pastesOnSelect, false) }
        set { write(\.pastesOnSelect, Keys.pastesOnSelect, newValue) }
    }
}

extension ClipboardSettings {
    enum Keys {
        static let enabled = "clipboard.enabled"
        static let persistsToDisk = "clipboard.persistsToDisk"
        static let pastesOnSelect = "clipboard.pastesOnSelect"
    }
}
