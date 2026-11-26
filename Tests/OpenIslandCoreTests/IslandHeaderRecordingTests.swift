import Testing
@testable import OpenIslandCore

struct IslandHeaderRecordingTests {
    @Test func stopsWhenEarshotEnabled() {
        #expect(IslandHeaderRecording.action(ambientListenEnabled: true, mitamaAppInstalled: true) == .stop)
        #expect(IslandHeaderRecording.action(ambientListenEnabled: true, mitamaAppInstalled: false) == .stop)
    }

    @Test func opensMitamaWhenIdleAndInstalled() {
        #expect(IslandHeaderRecording.action(ambientListenEnabled: false, mitamaAppInstalled: true) == .openMitamaMenu)
    }

    @Test func startsOnIslandWhenIdleAndAppMissing() {
        #expect(IslandHeaderRecording.action(ambientListenEnabled: false, mitamaAppInstalled: false) == .startOnIsland)
    }
}