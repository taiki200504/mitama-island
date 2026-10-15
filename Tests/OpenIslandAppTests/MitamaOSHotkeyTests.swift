import AppKit
import Foundation
import Testing
@testable import OpenIslandApp

@MainActor
struct MitamaOSHotkeyTests {
    @Test func registersAndRoutesGlobalShortcut() {
        let registrar = RecordingHotkeyRegistrar()
        let suite = "MitamaOSHotkeyTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ShortcutSettings(store: PreferenceStore(suite: defaults))
        settings.keyboardShortcutsEnabled = true
        let coordinator = PanelHotkeyCoordinator(registrar: registrar, settings: settings)
        var opened = false
        coordinator.onOpenMitamaOS = { opened = true }
        coordinator.startPersistentBindings()
        let binding = registrar.bindingsByScope[.persistent]?.first { $0.id == PanelHotkeyCoordinator.mitamaOSBindingID }
        #expect(binding?.keyCode == 46)
        #expect(binding?.modifiers == [.control, .option])
        registrar.onFire?(PanelHotkeyCoordinator.mitamaOSBindingID)
        #expect(opened)
        coordinator.setEnabled(false, panelIsExpanded: false)
        #expect(registrar.bindingsByScope[.persistent]?.isEmpty == true)
    }
}
