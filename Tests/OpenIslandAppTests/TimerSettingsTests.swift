import Foundation
import Testing
@testable import OpenIslandApp

/// The eye break must stay a deliberate opt-in, matching every other setting
/// that can start something on its own — a timer that begins running before
/// anyone asked for it would be a surprise the first time it interrupts.
@MainActor
struct TimerSettingsTests {
    private func makeSettings() -> TimerSettings {
        let name = "timer-settings-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return TimerSettings(store: PreferenceStore(suite: suite))
    }

    @Test
    func defaults() {
        let settings = makeSettings()

        #expect(settings.eyeBreakEnabled == false)
        #expect(settings.playsSound == true)
        #expect(settings.autoAdvance == true)
    }

    @Test
    func valuesPersistAcrossInstances() {
        let name = "timer-settings-persist-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        let store = PreferenceStore(suite: suite)

        let first = TimerSettings(store: store)
        first.eyeBreakEnabled = true
        first.playsSound = false
        first.autoAdvance = false

        let second = TimerSettings(store: store)
        #expect(second.eyeBreakEnabled == true)
        #expect(second.playsSound == false)
        #expect(second.autoAdvance == false)
    }
}
