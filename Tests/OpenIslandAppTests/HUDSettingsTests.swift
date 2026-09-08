import Foundation
import Testing
@testable import OpenIslandApp

@Suite("HUDSettings")
struct HUDSettingsTests {
    private func makeStore() -> PreferenceStore {
        let name = "hud-settings-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return PreferenceStore(suite: suite)
    }

    @Test("replacesSystem is off by default — turning macOS's own OSD off is not something to do silently")
    func replacesSystemOffByDefault() {
        #expect(HUDSettings(store: makeStore()).replacesSystem == false)
    }

    @Test("Volume and brightness default on, the keyboard backlight defaults off")
    func perMeterDefaults() {
        let settings = HUDSettings(store: makeStore())
        #expect(settings.volume)
        #expect(settings.brightness)
        #expect(!settings.keyboardBacklight)
    }

    @Test("Every switch persists across separate instances backed by the same store")
    func persistsAcrossInstancesOfTheSameStore() {
        let store = makeStore()
        let first = HUDSettings(store: store)
        first.replacesSystem = true
        first.volume = false
        first.keyboardBacklight = true

        let second = HUDSettings(store: store)
        #expect(second.replacesSystem)
        #expect(!second.volume)
        #expect(second.keyboardBacklight)
    }

    @Test("An explicit value for playsFeedbackSound overrides whatever the live system preference says")
    func explicitPlaysFeedbackSoundOverridesTheSystemDefault() {
        let settings = HUDSettings(store: makeStore())
        settings.playsFeedbackSound = false
        #expect(settings.playsFeedbackSound == false)
        settings.playsFeedbackSound = true
        #expect(settings.playsFeedbackSound == true)
    }
}
