import AppKit
import Foundation
import Observation

/// The single modifier every panel shortcut is held with.
///
/// The reference product does not ask for a full key combination per action —
/// one modifier is chosen once, then each action owns a single letter. Holding
/// that modifier is also what reveals the hints on the panel's buttons.
enum ShortcutModifier: String, CaseIterable, PreferenceRepresentable, Sendable {
    case control
    case option
    case command
    case shift

    var symbol: String {
        switch self {
        case .control: "⌃"
        case .option:  "⌥"
        case .command: "⌘"
        case .shift:   "⇧"
        }
    }

    var labelKey: String { "settings.shortcuts.modifier.\(rawValue)" }

    var flags: NSEvent.ModifierFlags {
        switch self {
        case .control: .control
        case .option:  .option
        case .command: .command
        case .shift:   .shift
        }
    }
}

/// An action reachable from the expanded panel.
enum PanelShortcutAction: String, CaseIterable, Sendable {
    case approve
    case deny
    case alwaysAllow
    case acceptEdits
    case skipPermissions
    case jumpToTerminal

    var labelKey: String { "settings.shortcuts.action.\(rawValue)" }

    /// Matches the reference product's out-of-the-box assignment.
    var defaultKey: String {
        switch self {
        case .approve:         "Y"
        case .deny:            "N"
        case .alwaysAllow:     "A"
        case .acceptEdits:     "E"
        case .skipPermissions: "B"
        case .jumpToTerminal:  "T"
        }
    }

    var preferenceKey: String { "shortcuts.panel.\(rawValue)" }
}

/// An action whose key is not the user's to choose.
enum FixedPanelShortcut: String, CaseIterable, Sendable {
    case selectOption
    case submitMultiSelect
    case collapsePanel

    var labelKey: String { "settings.shortcuts.action.\(rawValue)" }

    /// Whether the shared modifier applies. Escape stands alone.
    var usesModifier: Bool { self != .collapsePanel }

    var keyLabel: String {
        switch self {
        case .selectOption:      "1–9"
        case .submitMultiSelect: "↩"
        case .collapsePanel:     "esc"
        }
    }
}

/// Keyboard assignments for the panel and the session switcher.
final class ShortcutSettings: PreferenceGroup {
    let registrar = ObservationRegistrar()
    let store: PreferenceStore

    init(store: PreferenceStore = .standard) {
        self.store = store
    }

    var keyboardShortcutsEnabled: Bool {
        get { read(\.keyboardShortcutsEnabled, Keys.enabled, true) }
        set { write(\.keyboardShortcutsEnabled, Keys.enabled, newValue) }
    }

    var modifier: ShortcutModifier {
        get { read(\.modifier, Keys.modifier, .control) }
        set { write(\.modifier, Keys.modifier, newValue) }
    }

    var reverseSwitcherEnabled: Bool {
        get { read(\.reverseSwitcherEnabled, Keys.reverseSwitcher, true) }
        set { write(\.reverseSwitcherEnabled, Keys.reverseSwitcher, newValue) }
    }

    /// The letter held alongside `modifier` for a given panel action.
    ///
    /// Assignments are looked up by action rather than through a stored property,
    /// so they share one observation anchor: reading any key subscribes to the
    /// whole set, and changing any key notifies everyone reading it.
    func key(for action: PanelShortcutAction) -> String {
        registrar.access(self, keyPath: \.assignmentsRevision)
        return store.value(action.preferenceKey, default: action.defaultKey)
    }

    func setKey(_ key: String, for action: PanelShortcutAction) {
        let normalised = Self.normalise(key)
        guard !normalised.isEmpty else { return }
        registrar.withMutation(of: self, keyPath: \.assignmentsRevision) {
            store.setValue(normalised, forKey: action.preferenceKey)
        }
    }

    /// Observation anchor for the assignment set. Never read for its value.
    var assignmentsRevision: Int {
        store.value(Keys.revision, default: 0)
    }

    func resetToDefaults() {
        registrar.withMutation(of: self, keyPath: \.assignmentsRevision) {
            for action in PanelShortcutAction.allCases {
                store.removeValue(forKey: action.preferenceKey)
            }
            store.removeValue(forKey: Keys.modifier)
        }
    }

    var isCustomised: Bool {
        store.hasValue(forKey: Keys.modifier)
            || PanelShortcutAction.allCases.contains { store.hasValue(forKey: $0.preferenceKey) }
    }

    /// A single upper-case character; anything else is rejected rather than
    /// stored as an assignment that could never match a key press.
    static func normalise(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let first = trimmed.first, trimmed.count == 1, first.isLetter || first.isNumber else {
            return ""
        }
        return String(first)
    }
}

extension ShortcutSettings {
    enum Keys {
        static let enabled = "shortcuts.enabled"
        static let modifier = "shortcuts.modifier"
        static let reverseSwitcher = "shortcuts.reverseSwitcher"
        static let revision = "shortcuts.assignmentsRevision"
    }
}
