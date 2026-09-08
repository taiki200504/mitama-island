import Foundation
import Testing
@testable import OpenIslandApp

/// Every switch here has to default off — see `ClipboardSettings`'s own
/// doc comment on why watching everything copied on the machine is not a
/// thing to switch on without being asked.
@MainActor
struct ClipboardSettingsTests {
    private func makeSettings() -> ClipboardSettings {
        let name = "clipboard-settings-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return ClipboardSettings(store: PreferenceStore(suite: suite))
    }

    @Test
    func defaultsAreAllOff() {
        let settings = makeSettings()

        #expect(settings.enabled == false)
        #expect(settings.persistsToDisk == false)
        #expect(settings.pastesOnSelect == false)
    }

    @Test
    func valuesPersistAcrossInstances() {
        let name = "clipboard-settings-persist-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        let store = PreferenceStore(suite: suite)

        let first = ClipboardSettings(store: store)
        first.enabled = true
        first.persistsToDisk = true
        first.pastesOnSelect = true

        let second = ClipboardSettings(store: store)
        #expect(second.enabled == true)
        #expect(second.persistsToDisk == true)
        #expect(second.pastesOnSelect == true)
    }
}
