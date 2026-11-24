import Foundation
import Testing
@testable import OpenIslandCore

@Suite struct MeetingCaptureTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    private var context: MeetingContext {
        MeetingContext(
            source: .app, appBundleID: "us.zoom.xos", appName: "zoom.us",
            title: "Weekly", calendar: nil, startedAt: start
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("meeting-capture-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Folder id and file names follow the local start time")
    func layout() {
        let layout = MeetingRecordingLayout(startedAt: start, timeZone: tokyo)
        // 1_800_000_000 = 2027-01-15 08:00:00 UTC = 17:00:00 JST
        #expect(layout.id == "20270115-170000")
        #expect(layout.micFileName == "20270115-170000.mic.m4a")
        #expect(layout.systemFileName == "20270115-170000.sys.m4a")
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        #expect(MeetingRecordingLayout.defaultRecordingsRoot(home: home).path == "/Users/me/Library/Application Support/mitama/meetings")
        #expect(MeetingRecordingLayout.defaultInbox(home: home).path == "/Users/me/.mitama/meetings/inbox")
    }

    @Test("A typed inbox path expands ~ and falls back to the default when blank")
    func expandTilde() {
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        #expect(MeetingRecordingLayout.expandTilde("~/x/inbox", home: home).path == "/Users/me/x/inbox")
        #expect(MeetingRecordingLayout.expandTilde("  ", home: home).path == "/Users/me/.mitama/meetings/inbox")
        #expect(MeetingRecordingLayout.expandTilde("/tmp/in", home: home).path == "/tmp/in")
    }

    @Test("The manifest encodes the snake_case contract mitama-os reads")
    func manifestKeys() throws {
        let manifest = MeetingManifest(
            id: "20270115-170000", context: context, endedAt: start.addingTimeInterval(1800),
            endReason: .micIdle, scope: .company,
            files: .init(mic: "20270115-170000.mic.m4a", sys: "20270115-170000.sys.m4a"),
            recordingDir: "/tmp/x"
        )
        let data = try MeetingManifest.encoder().encode(manifest)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["schema"] as? String == "mitama.meeting.v1")
        #expect(object["duration_seconds"] as? Double == 1800)
        #expect(object["end_reason"] as? String == "mic_idle")
        #expect(object["scope"] as? String == "company")
        #expect(object["source"] as? String == "app")
        #expect(object["third_party"] as? Bool == true)
        #expect(object["recording_dir"] as? String == "/tmp/x")
        #expect(object["started_at"] as? String != nil)
        #expect((object["app"] as? [String: Any])?["bundle_id"] as? String == "us.zoom.xos")
        #expect((object["files"] as? [String: Any])?["sys"] as? String == "20270115-170000.sys.m4a")
        #expect((object["channels"] as? [String: String]) == ["mic": "self", "sys": "others"])

        let decoded = try MeetingManifest.decoder().decode(MeetingManifest.self, from: data)
        #expect(decoded == manifest)
    }

    @Test("Delivery moves audio into the inbox atomically and leaves the manifest behind")
    func deliver() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let recording = root.appendingPathComponent("rec/20270115-170000", isDirectory: true)
        try FileManager.default.createDirectory(at: recording, withIntermediateDirectories: true)
        try Data("mic".utf8).write(to: recording.appendingPathComponent("20270115-170000.mic.m4a"))
        // No system audio: screen recording was refused.
        let inbox = root.appendingPathComponent("inbox", isDirectory: true)
        let manifest = MeetingManifest(
            id: "20270115-170000", context: context, endedAt: start.addingTimeInterval(60),
            endReason: .appClosed, scope: .personal,
            files: .init(mic: "20270115-170000.mic.m4a", sys: "20270115-170000.sys.m4a"),
            recordingDir: recording.path
        )

        let delivered = try MeetingInbox.deliver(manifest: manifest, from: recording, to: inbox)

        #expect(delivered.lastPathComponent == "20270115-170000")
        let names = try FileManager.default.contentsOfDirectory(atPath: delivered.path).sorted()
        #expect(names == ["20270115-170000.mic.m4a", "manifest.json"])
        #expect(!FileManager.default.fileExists(atPath: recording.appendingPathComponent("20270115-170000.mic.m4a").path))
        #expect(FileManager.default.fileExists(atPath: recording.appendingPathComponent("manifest.json").path))
        // No staging folder is left behind.
        let inboxNames = try FileManager.default.contentsOfDirectory(atPath: inbox.path)
        #expect(inboxNames == ["20270115-170000"])

        let data = try Data(contentsOf: delivered.appendingPathComponent("manifest.json"))
        let written = try MeetingManifest.decoder().decode(MeetingManifest.self, from: data)
        #expect(written.files.mic == "20270115-170000.mic.m4a")
        #expect(written.files.sys == nil)
    }

    @Test("A second delivery with the same id does not overwrite the first")
    func deliverCollision() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = root.appendingPathComponent("inbox", isDirectory: true)
        for index in 0..<2 {
            let recording = root.appendingPathComponent("rec\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: recording, withIntermediateDirectories: true)
            try Data("mic".utf8).write(to: recording.appendingPathComponent("a.mic.m4a"))
            let manifest = MeetingManifest(
                id: "same", context: context, endedAt: start, endReason: .micIdle, scope: .personal,
                files: .init(mic: "a.mic.m4a", sys: nil), recordingDir: recording.path
            )
            try MeetingInbox.deliver(manifest: manifest, from: recording, to: inbox)
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: inbox.path).sorted()
        #expect(names == ["same", "same-2"])
    }

    @Test("Nothing recorded means nothing is delivered")
    func deliverNothing() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = MeetingManifest(
            id: "x", context: context, endedAt: start, endReason: .micIdle, scope: .personal,
            files: .init(mic: "x.mic.m4a", sys: nil), recordingDir: root.path
        )
        #expect(throws: MeetingInbox.DeliveryError.nothingRecorded) {
            try MeetingInbox.deliver(manifest: manifest, from: root, to: root.appendingPathComponent("inbox"))
        }
    }

    @Test("summary.json decodes leniently, including JavaScript timestamps")
    func summaryDecoding() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(MeetingSummary.load(from: root) == nil)

        let json = """
        {"schema":"mitama.meeting.summary.v1","id":"20270115-170000","summary":"価格を決めた。",
         "decisions":["月額3万円"],"my_tasks":["見積もりを送る","資料"],"generated_at":"2026-11-24T06:00:00.000Z",
         "hub_url":"https://example.invalid/meetings/1","unknown_field":1}
        """
        try Data(json.utf8).write(to: root.appendingPathComponent("summary.json"))
        let summary = try #require(MeetingSummary.load(from: root))
        #expect(summary.summary == "価格を決めた。")
        #expect(summary.decisions == ["月額3万円"])
        #expect(summary.myTasks.count == 2)
        #expect(summary.aiRequests.isEmpty)
        #expect(summary.generatedAt == "2026-11-24T06:00:00.000Z")
        #expect(summary.countsLine == "決定 1 · タスク 2")
    }

    @Test("A half-written summary reads as not there yet")
    func summaryPartial() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("{\"summary\": \"half".utf8).write(to: root.appendingPathComponent("summary.json"))
        #expect(MeetingSummary.load(from: root) == nil)
    }

    @Test("Phase helpers")
    func phase() {
        let phase = MeetingCapturePhase.recording(id: "x", title: "t", startedAt: start)
        #expect(phase.isRecording)
        #expect(phase.recordingMinutes(at: start.addingTimeInterval(125)) == 2)
        #expect(MeetingCapturePhase.idle.recordingMinutes(at: start) == nil)
        #expect(MeetingCapturePhase.elapsedText(from: start, to: start.addingTimeInterval(65)) == "1:05")
        #expect(MeetingCapturePhase.elapsedText(from: start, to: start.addingTimeInterval(3725)) == "1:02:05")
        #expect(MeetingSummaryWatch.shouldKeepWaiting(endedAt: start, now: start.addingTimeInterval(60)))
        #expect(!MeetingSummaryWatch.shouldKeepWaiting(endedAt: start, now: start.addingTimeInterval(3 * 3600)))
    }

    @Test("A recording meeting outranks every other closed-island accessory")
    func closedAccessory() {
        let inputs = IslandClosedInputs(
            timer: .init(remainingMinutes: 5, label: "focus"),
            cameraIsWatching: true,
            shelfCount: 2,
            meetingRecordingMinutes: 12
        )
        #expect(IslandClosedArbiter.resolve(inputs).accessory == .meetingRecording(minutes: 12))
        let without = IslandClosedInputs(timer: .init(remainingMinutes: 5, label: "focus"))
        #expect(IslandClosedArbiter.resolve(without).accessory == .timer(remainingMinutes: 5, label: "focus"))
    }
}
