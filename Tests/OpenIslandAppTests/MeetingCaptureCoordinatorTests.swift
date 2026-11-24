import Foundation
import Testing
import OpenIslandCore
@testable import OpenIslandApp

@MainActor
private final class ScriptedSignalSource: MeetingSignalSource {
    var next: MeetingSignals?
    func snapshot(at now: Date) -> MeetingSignals {
        next ?? MeetingSignals(micInUse: false, at: now)
    }
}

@MainActor
private final class FakeRecorder: MeetingRecorder {
    var started = false
    var stopped = false
    var micURL: URL?

    func start(context: MeetingContext, micURL: URL, systemURL: URL) async throws {
        started = true
        self.micURL = micURL
        try Data("mic".utf8).write(to: micURL)
    }

    func stop() async -> MeetingRecordingResult {
        stopped = true
        return MeetingRecordingResult(micRecorded: true, systemRecorded: false)
    }
}

@MainActor
struct MeetingCaptureCoordinatorTests {
    private let zoom = MeetingSignals.RunningApp(bundleID: "us.zoom.xos", name: "zoom.us")

    private func makeSettings() -> MeetingCaptureSettings {
        let name = "meeting-capture-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return MeetingCaptureSettings(store: PreferenceStore(suite: suite))
    }

    private func makeHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("meeting-coordinator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test
    func defaultsRecordEverythingWithAnEmptyList() {
        let settings = makeSettings()
        #expect(settings.isEnabled)
        #expect(settings.doNotRecordText.isEmpty)
        #expect(settings.inboxPath == "~/.mitama/meetings/inbox")
        #expect(MeetingRuleList.parse(settings.companyKeywordsText) == ["Gugen", "マカセタ"])
    }

    @Test
    func meetingIsRecordedAndHandedToTheInbox() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let settings = makeSettings()
        let source = ScriptedSignalSource()
        let recorder = FakeRecorder()
        let coordinator = MeetingCaptureCoordinator(settings: settings, source: source, makeRecorder: { recorder }, home: home)
        let start = Date()

        source.next = MeetingSignals(micInUse: true, runningApps: [zoom], at: start)
        coordinator.tick(now: start)
        #expect(coordinator.phase.isRecording)
        await waitUntil { recorder.started }

        // Zoom quits: the meeting ends and is handed off.
        source.next = MeetingSignals(micInUse: false, runningApps: [], at: start.addingTimeInterval(5))
        coordinator.tick(now: start.addingTimeInterval(5))
        await waitUntil {
            if case .processing = coordinator.phase { return true }
            return false
        }
        #expect(recorder.stopped)

        let inbox = home.appendingPathComponent(".mitama/meetings/inbox", isDirectory: true)
        let delivered = try FileManager.default.contentsOfDirectory(atPath: inbox.path)
        #expect(delivered.count == 1)
        let folder = inbox.appendingPathComponent(try #require(delivered.first))
        let data = try Data(contentsOf: folder.appendingPathComponent("manifest.json"))
        let manifest = try MeetingManifest.decoder().decode(MeetingManifest.self, from: data)
        #expect(manifest.endReason == .appClosed)
        #expect(manifest.scope == .personal)
        #expect(manifest.files.sys == nil)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(manifest.files.mic ?? "").path))
    }

    @Test
    func discardDeletesTheRecording() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let source = ScriptedSignalSource()
        let recorder = FakeRecorder()
        let coordinator = MeetingCaptureCoordinator(settings: makeSettings(), source: source, makeRecorder: { recorder }, home: home)
        let start = Date()

        source.next = MeetingSignals(micInUse: true, runningApps: [zoom], at: start)
        coordinator.tick(now: start)
        await waitUntil { recorder.started }
        let folder = try #require(recorder.micURL).deletingLastPathComponent()

        coordinator.discardRecording()
        #expect(coordinator.phase == .idle)
        await waitUntil { !FileManager.default.fileExists(atPath: folder.path) }
        #expect(!FileManager.default.fileExists(atPath: folder.path))

        // Still the same call: it is not picked up again.
        coordinator.tick(now: start.addingTimeInterval(10))
        #expect(coordinator.phase == .idle)
    }

    @Test
    func doNotRecordListSkipsTheMeeting() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let settings = makeSettings()
        settings.doNotRecordText = "zoom.us"
        let source = ScriptedSignalSource()
        let recorder = FakeRecorder()
        let coordinator = MeetingCaptureCoordinator(settings: settings, source: source, makeRecorder: { recorder }, home: home)
        source.next = MeetingSignals(micInUse: true, runningApps: [zoom], at: Date())
        coordinator.tick(now: Date())
        #expect(coordinator.phase == .idle)
        #expect(!recorder.started)
    }
}
