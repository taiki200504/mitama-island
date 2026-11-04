import Foundation
import Testing
@testable import OpenIslandApp

struct TravelModeAudioTests {
    @Test @MainActor func suspensionNeverChangesTheOwnersRecordingPreference() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = AmbientListenSettings(store: PreferenceStore(suite: defaults))
        let session = AmbientListenSession(settings: settings)
        session.setTravelSuspended(true)
        settings.isEnabled = true
        session.settingsChanged()
        session.start()
        #expect(settings.isEnabled)
        #expect(!session.isRunning)
        // An OFF preference changed during travel wins over the old ON value.
        settings.isEnabled = false
        session.setTravelSuspended(false)
        #expect(!settings.isEnabled)
        #expect(!session.isRunning)
    }

    @Test @MainActor func offlineRelaunchWithRecoveryMarkerSuspendsCapture() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("travel-mode.json")
        try Data(#"{"address":"00-11-22-33-44-55","wasConnected":true}"#.utf8).write(to: url)
        let settings = AmbientListenSettings(store: PreferenceStore(suite: UserDefaults(suiteName: UUID().uuidString)!))
        let session = AmbientListenSession(settings: settings)
        let controller = TravelModeController(session: session, stateURL: url)
        settings.isEnabled = true
        session.start()
        #expect(!session.isRunning)
        #expect(settings.isEnabled)
        withExtendedLifetime(controller) {}
    }

    @Test @MainActor func corruptRecoveryMarkerDoesNotStartTheMicrophone() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("broken".utf8).write(to: url)
        let settings = AmbientListenSettings(store: PreferenceStore(suite: UserDefaults(suiteName: UUID().uuidString)!))
        let session = AmbientListenSession(settings: settings)
        let controller = TravelModeController(session: session, stateURL: url)
        settings.isEnabled = true
        session.settingsChanged()
        #expect(!session.isRunning)
        withExtendedLifetime(controller) {}
    }
}
