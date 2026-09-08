import Foundation
import Testing
@testable import OpenIslandApp

/// The camera-opening half of the unlock greeting must stay a deliberate
/// opt-in, same discipline as every other switch in this app that can open
/// the camera outside a keypress.
@MainActor
struct LockScanSettingsTests {
    private func makeSettings() -> LockScanSettings {
        let name = "lock-scan-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return LockScanSettings(store: PreferenceStore(suite: suite))
    }

    @Test("The greeting itself defaults on, the camera check defaults off")
    func defaults() {
        let settings = makeSettings()

        #expect(settings.enabled)
        #expect(settings.usesCamera == false)
    }

    @Test("Both switches persist independently")
    func persistsIndependently() {
        let settings = makeSettings()

        settings.enabled = false
        settings.usesCamera = true

        #expect(settings.enabled == false)
        #expect(settings.usesCamera)
    }
}
