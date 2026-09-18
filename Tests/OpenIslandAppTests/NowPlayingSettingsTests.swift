import Foundation
import Testing
@testable import OpenIslandApp

/// Now Playing only ever reflects whatever's already playing elsewhere — it
/// never starts anything on its own, so it's the one feature here that
/// defaults fully on rather than needing an opt-in.
@MainActor
struct NowPlayingSettingsTests {
    private func makeSettings() -> NowPlayingSettings {
        let name = "now-playing-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return NowPlayingSettings(store: PreferenceStore(suite: suite))
    }

    @Test("Every switch defaults on")
    func defaults() {
        let settings = makeSettings()

        #expect(settings.enabled)
        #expect(settings.showsInClosedIsland)
        #expect(settings.sneakPeekOnTrackChange)
    }

    @Test("Every switch persists independently")
    func persistsIndependently() {
        let settings = makeSettings()

        settings.enabled = false
        settings.showsInClosedIsland = false
        settings.sneakPeekOnTrackChange = false

        #expect(settings.enabled == false)
        #expect(settings.showsInClosedIsland == false)
        #expect(settings.sneakPeekOnTrackChange == false)
    }
}
