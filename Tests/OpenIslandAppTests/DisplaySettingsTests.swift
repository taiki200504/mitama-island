import Foundation
import Testing
@testable import OpenIslandApp

@MainActor
struct DisplaySettingsTests {
    private func makeSettings() -> SettingsStore {
        let name = "display-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return SettingsStore(store: PreferenceStore(suite: suite))
    }

    @Test("Alerting when an event starts defaults to on, independent of the next-event setting")
    func alertsWhenEventStartsDefaultsOn() {
        let display = makeSettings().display
        #expect(display.alertsWhenEventStarts)
        #expect(!display.showsNextEvent)
    }

    @Test("The choice persists across a fresh read of the same store")
    func alertsWhenEventStartsPersists() {
        let store = PreferenceStore(suite: UserDefaults(suiteName: "display-persist-\(UUID().uuidString)")!)
        DisplaySettings(store: store).alertsWhenEventStarts = false
        #expect(!DisplaySettings(store: store).alertsWhenEventStarts)
    }
}
