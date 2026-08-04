import AppKit
import Foundation
import Testing
@testable import OpenIslandApp

/// Records what would have been registered, so the rules can be checked without
/// taking a system-wide key away from whatever else is running.
@MainActor
final class RecordingHotkeyRegistrar: HotkeyRegistering {
    var onFire: ((String) -> Void)?
    private(set) var bindingsByScope: [HotkeyScope: [HotkeyBinding]] = [:]
    private(set) var removals: [HotkeyScope] = []

    func setBindings(_ bindings: [HotkeyBinding], for scope: HotkeyScope) {
        bindingsByScope[scope] = bindings
    }

    func removeBindings(for scope: HotkeyScope) {
        removals.append(scope)
        bindingsByScope[scope] = []
    }
}

@Suite("Keycode resolution")
struct KeycodeResolverTests {
    private let resolver = KeycodeResolver(table: KeycodeResolver.usFallbackTable)

    @Test("A letter resolves to its key position")
    func resolvesLetters() {
        #expect(resolver.keyCode(for: "Y") == 16)
        #expect(resolver.keyCode(for: "N") == 45)
    }

    @Test("Case and stray spaces do not matter")
    func normalisesInput() {
        #expect(resolver.keyCode(for: "y") == 16)
        #expect(resolver.keyCode(for: " Y ") == 16)
    }

    /// A layout genuinely lacking the letter must return nil so the settings
    /// pane can say so, rather than registering some other key.
    @Test("An absent letter resolves to nothing")
    func missingLetter() {
        let sparse = KeycodeResolver(table: ["A": 0])
        #expect(sparse.keyCode(for: "Z") == nil)
    }

    @Test("Anything longer than one character is rejected")
    func rejectsMultiCharacter() {
        #expect(resolver.keyCode(for: "YY") == nil)
        #expect(resolver.keyCode(for: "") == nil)
    }
}

@Suite("Panel hotkey coordinator", .serialized)
@MainActor
struct PanelHotkeyCoordinatorTests {
    private func makeCoordinator(
        _ configure: (ShortcutSettings) -> Void = { _ in }
    ) -> (PanelHotkeyCoordinator, RecordingHotkeyRegistrar, ShortcutSettings) {
        let defaults = UserDefaults(suiteName: "hotkey-\(UUID().uuidString)")!
        let settings = ShortcutSettings(store: PreferenceStore(suite: defaults))
        configure(settings)
        let registrar = RecordingHotkeyRegistrar()
        let coordinator = PanelHotkeyCoordinator(
            registrar: registrar,
            settings: settings,
            resolver: KeycodeResolver(table: KeycodeResolver.usFallbackTable)
        )
        return (coordinator, registrar, settings)
    }

    @Test("Every default action gets a binding")
    func registersDefaults() {
        let (coordinator, registrar, _) = makeCoordinator()
        coordinator.panelDidExpand()
        let bindings = registrar.bindingsByScope[.panelExpanded] ?? []
        #expect(bindings.count == PanelShortcutAction.allCases.count)
        #expect(Set(bindings.map(\.id)) == Set(PanelShortcutAction.allCases.map(\.rawValue)))
    }

    /// The safety property this whole design exists for: a single letter must
    /// not be ours while the user is typing in an editor.
    @Test("Bindings live only while the panel is expanded")
    func scopedToTheExpandedPanel() {
        let (coordinator, registrar, _) = makeCoordinator()
        coordinator.panelDidExpand()
        #expect(registrar.bindingsByScope[.panelExpanded]?.isEmpty == false)

        coordinator.panelDidCollapse()
        #expect(registrar.removals.contains(.panelExpanded))
        #expect(registrar.bindingsByScope[.panelExpanded]?.isEmpty == true)
    }

    @Test("The chosen modifier is the one registered")
    func usesConfiguredModifier() {
        let (coordinator, registrar, _) = makeCoordinator { $0.modifier = .option }
        coordinator.panelDidExpand()
        let binding = registrar.bindingsByScope[.panelExpanded]?.first
        #expect(binding?.modifiers == NSEvent.ModifierFlags.option)
    }

    /// Registering the same key twice would make which action fires depend on
    /// iteration order. The second one is dropped and reported instead.
    @Test("Two actions on one letter register once and the clash is reported")
    func duplicateKeysAreDropped() {
        let (coordinator, registrar, _) = makeCoordinator {
            $0.setKey("Y", for: .approve)
            $0.setKey("Y", for: .deny)
        }
        coordinator.panelDidExpand()
        let bindings = registrar.bindingsByScope[.panelExpanded] ?? []
        #expect(bindings.filter { $0.keyCode == 16 }.count == 1)
        #expect(coordinator.unresolvableActions().contains(.deny))
    }

    @Test("A letter the layout lacks is reported, not registered")
    func unresolvableLettersAreReported() {
        let defaults = UserDefaults(suiteName: "hotkey-\(UUID().uuidString)")!
        let settings = ShortcutSettings(store: PreferenceStore(suite: defaults))
        let coordinator = PanelHotkeyCoordinator(
            registrar: RecordingHotkeyRegistrar(),
            settings: settings,
            resolver: KeycodeResolver(table: ["Y": 16])
        )
        #expect(coordinator.bindings().count == 1)
        #expect(coordinator.unresolvableActions().contains(.deny))
    }

    @Test("Turning shortcuts off registers nothing")
    func disabledRegistersNothing() {
        let (coordinator, registrar, _) = makeCoordinator { $0.keyboardShortcutsEnabled = false }
        coordinator.panelDidExpand()
        #expect((registrar.bindingsByScope[.panelExpanded] ?? []).isEmpty)
    }

    @Test("A fired binding maps back to its action")
    func firingRoutesToTheAction() {
        let (coordinator, registrar, _) = makeCoordinator()
        var fired: PanelShortcutAction?
        coordinator.onAction = { fired = $0 }
        registrar.onFire?(PanelShortcutAction.approve.rawValue)
        #expect(fired == .approve)
    }

    @Test("An unknown identifier fires nothing")
    func unknownIdentifierIsIgnored() {
        let (coordinator, registrar, _) = makeCoordinator()
        var fired: PanelShortcutAction?
        coordinator.onAction = { fired = $0 }
        registrar.onFire?("notAnAction")
        #expect(fired == nil)
    }
}

@Suite("Switcher hotkey registration", .serialized)
@MainActor
struct SwitcherHotkeyTests {
    private func makeCoordinator(
        _ configure: (ShortcutSettings) -> Void = { _ in }
    ) -> (PanelHotkeyCoordinator, RecordingHotkeyRegistrar) {
        let defaults = UserDefaults(suiteName: "switcher-\(UUID().uuidString)")!
        let settings = ShortcutSettings(store: PreferenceStore(suite: defaults))
        configure(settings)
        let registrar = RecordingHotkeyRegistrar()
        return (
            PanelHotkeyCoordinator(
                registrar: registrar,
                settings: settings,
                resolver: KeycodeResolver(table: KeycodeResolver.usFallbackTable)
            ),
            registrar
        )
    }

    @Test("The switcher key is the one always-live shortcut")
    func switcherIsPersistent() {
        let (coordinator, registrar) = makeCoordinator()
        coordinator.startPersistentBindings()
        let ids = (registrar.bindingsByScope[.persistent] ?? []).map(\.id)
        #expect(ids.contains(PanelHotkeyCoordinator.switcherBindingID))
    }

    @Test("Turning reverse off drops its binding")
    func reverseIsOptional() {
        let (coordinator, registrar) = makeCoordinator { $0.reverseSwitcherEnabled = false }
        coordinator.startPersistentBindings()
        let ids = (registrar.bindingsByScope[.persistent] ?? []).map(\.id)
        #expect(!ids.contains(PanelHotkeyCoordinator.switcherReverseBindingID))
    }

    /// Escape and the arrows are far too common to hold system-wide. They may
    /// only exist while the switcher is actually on screen.
    @Test("Arrows and escape live only while the switcher is up")
    func navigationKeysAreScoped() {
        let (coordinator, registrar) = makeCoordinator()
        coordinator.startPersistentBindings()
        #expect((registrar.bindingsByScope[.switcherActive] ?? []).isEmpty)

        coordinator.switcherDidActivate()
        #expect((registrar.bindingsByScope[.switcherActive] ?? []).count == 4)

        coordinator.switcherDidDeactivate()
        #expect(registrar.removals.contains(.switcherActive))
    }

    @Test("Shift routes to the reverse direction")
    func reverseRoutes() {
        let (coordinator, registrar) = makeCoordinator()
        var reversed: Bool?
        coordinator.onSwitcherKey = { reversed = $0 }

        registrar.onFire?(PanelHotkeyCoordinator.switcherBindingID)
        #expect(reversed == false)
        registrar.onFire?(PanelHotkeyCoordinator.switcherReverseBindingID)
        #expect(reversed == true)
    }

    @Test("Escape cancels rather than confirming")
    func escapeCancels() {
        let (coordinator, registrar) = makeCoordinator()
        var confirmed = false
        var cancelled = false
        coordinator.onSwitcherConfirm = { confirmed = true }
        coordinator.onSwitcherCancel = { cancelled = true }

        registrar.onFire?(PanelHotkeyCoordinator.switcherCancelBindingID)
        #expect(cancelled)
        #expect(confirmed == false)
    }
}
