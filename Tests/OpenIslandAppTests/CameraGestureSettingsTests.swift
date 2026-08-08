import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// Touchless activation must remain a deliberate opt-in: a camera prompt from
/// a feature someone never enabled would make the safety setting meaningless.
@MainActor
struct CameraGestureSettingsTests {
    private func makeSettings() -> CameraGestureSettings {
        let name = "camera-gesture-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return CameraGestureSettings(store: PreferenceStore(suite: suite))
    }

    @Test
    func defaultsKeepCameraActivationOff() {
        let settings = makeSettings()

        #expect(settings.isEnabled == false)
        #expect(settings.requiresFaceMatch)
        #expect(settings.windowSeconds == 5.0)
        #expect(settings.faceMatchThreshold == FaceReference.defaultMatchThreshold)
    }

    @Test
    func windowSecondsStaysWithinActivationBounds() {
        let settings = makeSettings()

        settings.windowSeconds = -1
        #expect(settings.windowSeconds == 1.0)

        settings.windowSeconds = 20
        #expect(settings.windowSeconds == 15.0)
    }
}
