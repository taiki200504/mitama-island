import Foundation
import Observation
import Testing
@testable import OpenIslandApp

/// The shortcuts pane stores assignments today and fires none of them, so these
/// tests cover the storage and the honesty of the pending markers rather than
/// any key actually working.
@MainActor
struct ShortcutSettingsTests {
    private func makeSettings() -> ShortcutSettings {
        let name = "shortcuts-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return ShortcutSettings(store: PreferenceStore(suite: suite))
    }

    private final class ChangeCounter: @unchecked Sendable {
        private(set) var count = 0
        func increment() { count += 1 }
    }

    @Test
    func defaultsMatchTheReferenceProduct() {
        let shortcuts = makeSettings()

        #expect(shortcuts.modifier == .control)
        #expect(shortcuts.key(for: .approve) == "Y")
        #expect(shortcuts.key(for: .deny) == "N")
        #expect(shortcuts.key(for: .alwaysAllow) == "A")
        #expect(shortcuts.key(for: .skipPermissions) == "B")
        #expect(shortcuts.key(for: .jumpToTerminal) == "T")
    }

    @Test
    func assignmentsPersist() {
        let shortcuts = makeSettings()
        shortcuts.setKey("k", for: .approve)

        #expect(shortcuts.key(for: .approve) == "K")
        #expect(shortcuts.key(for: .deny) == "N")
    }

    /// An assignment that could never match a key press must be refused rather
    /// than stored, or the row would show something that can never fire.
    @Test
    func unusableAssignmentsAreRejected() {
        let shortcuts = makeSettings()

        for candidate in ["", " ", "AB", "⌘", "!"] {
            shortcuts.setKey(candidate, for: .approve)
            #expect(shortcuts.key(for: .approve) == "Y", "accepted \(candidate)")
        }

        shortcuts.setKey("7", for: .approve)
        #expect(shortcuts.key(for: .approve) == "7")
    }

    @Test
    func normaliseUppercasesASingleCharacter() {
        #expect(ShortcutSettings.normalise(" q ") == "Q")
        #expect(ShortcutSettings.normalise("Z") == "Z")
        #expect(ShortcutSettings.normalise("qq").isEmpty)
    }

    @Test
    func resetRestoresEveryDefault() {
        let shortcuts = makeSettings()
        shortcuts.setKey("K", for: .approve)
        shortcuts.modifier = .command
        #expect(shortcuts.isCustomised)

        shortcuts.resetToDefaults()

        #expect(!shortcuts.isCustomised)
        #expect(shortcuts.modifier == .control)
        #expect(shortcuts.key(for: .approve) == "Y")
    }

    /// Assignments are read through a function, not a stored property, so they
    /// need an explicit observation anchor or the pane would not redraw.
    @Test
    func changingAnAssignmentNotifiesReaders() {
        let shortcuts = makeSettings()
        let counter = ChangeCounter()

        withObservationTracking {
            _ = shortcuts.key(for: .approve)
        } onChange: {
            counter.increment()
        }

        shortcuts.setKey("K", for: .approve)
        #expect(counter.count == 1)
    }

    @Test
    func resetNotifiesReaders() {
        let shortcuts = makeSettings()
        shortcuts.setKey("K", for: .approve)

        let counter = ChangeCounter()
        withObservationTracking {
            _ = shortcuts.key(for: .approve)
        } onChange: {
            counter.increment()
        }

        shortcuts.resetToDefaults()
        #expect(counter.count == 1)
    }

    @Test
    func everyActionAndModifierHasAVisibleLabel() {
        for action in PanelShortcutAction.allCases {
            #expect(LanguageManager.shared.t(action.labelKey) != action.labelKey)
        }
        for fixed in FixedPanelShortcut.allCases {
            #expect(LanguageManager.shared.t(fixed.labelKey) != fixed.labelKey)
        }
        for modifier in ShortcutModifier.allCases {
            #expect(LanguageManager.shared.t(modifier.labelKey) != modifier.labelKey)
        }
    }

    /// Escape stands alone; everything else is held with the shared modifier.
    @Test
    func onlyTheClosePanelKeyIgnoresTheModifier() {
        #expect(!FixedPanelShortcut.collapsePanel.usesModifier)
        #expect(FixedPanelShortcut.selectOption.usesModifier)
        #expect(FixedPanelShortcut.submitMultiSelect.usesModifier)
    }

    /// The five assignable actions fire now. What is left needs the panel to
    /// take keyboard focus, or a switcher that does not exist yet — when either
    /// lands, those rows have to stop being disabled.
    @Test
    func whatStillDoesNotFire() {
        #expect(!PendingCapability.inPanelTypedKeys.isImplemented)
    }
}
