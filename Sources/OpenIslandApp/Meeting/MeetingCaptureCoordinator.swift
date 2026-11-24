import Foundation
import Observation
import OpenIslandCore
import os

/// Detects meetings, records them, and hands the files to mitama-os.
///
/// All decisions live in `MeetingDetector` (core); this class only polls the
/// signal source, drives a `MeetingRecorder`, and moves files. The flow:
///
/// 1. every 5 s: snapshot → detector
/// 2. `meetingStarted` → new folder under Application Support, recorder starts,
///    island shows 録音中 with stop / discard
/// 3. `meetingEnded` or stop → recorder stops, `manifest.json` written, audio
///    moved to the inbox (`MeetingInbox.deliver`), island says the notes are
///    being made
/// 4. every 15 s until `summary.json` appears next to the manifest → island
///    shows the summary
///
/// Separate from earshot on purpose: earshot pauses during calls, this is what
/// records them.
@MainActor
@Observable
final class MeetingCaptureCoordinator {
    private static let logger = Logger(subsystem: "com.mitama.island", category: "meeting")
    static let pollInterval: Duration = .seconds(5)

    private(set) var phase: MeetingCapturePhase = .idle

    /// Puts a sentence on the island. Set by the app at launch.
    @ObservationIgnored var onNotice: ((String) -> Void)?

    @ObservationIgnored private let settings: MeetingCaptureSettings
    @ObservationIgnored private let source: any MeetingSignalSource
    @ObservationIgnored private let makeRecorder: @MainActor () -> any MeetingRecorder
    @ObservationIgnored private let recordingsRoot: URL
    @ObservationIgnored private let home: URL
    @ObservationIgnored private var detector = MeetingDetector()
    @ObservationIgnored private var poll: Task<Void, Never>?
    @ObservationIgnored private var summaryWatch: Task<Void, Never>?
    @ObservationIgnored private var active: ActiveRecording?

    private struct ActiveRecording {
        let layout: MeetingRecordingLayout
        let directory: URL
        let context: MeetingContext
        let recorder: any MeetingRecorder
        let startTask: Task<Bool, Never>
    }

    init(
        settings: MeetingCaptureSettings,
        source: any MeetingSignalSource,
        makeRecorder: @escaping @MainActor () -> any MeetingRecorder,
        home: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        recordingsRoot: URL? = nil
    ) {
        self.settings = settings
        self.source = source
        self.makeRecorder = makeRecorder
        self.home = home
        self.recordingsRoot = recordingsRoot ?? MeetingRecordingLayout.defaultRecordingsRoot(home: home)
    }

    var inboxURL: URL {
        MeetingRecordingLayout.expandTilde(settings.inboxPath, home: home)
    }

    // MARK: Lifecycle

    /// Starts watching for meetings. Does nothing while the switch is off.
    func start() {
        guard settings.isEnabled, poll == nil else { return }
        poll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.tick(now: .now)
                do { try await Task.sleep(for: Self.pollInterval) } catch { return }
            }
        }
        Self.logger.notice("meeting capture watching")
    }

    /// Stops watching. A meeting being recorded is finished and handed off,
    /// not thrown away.
    func stop() {
        poll?.cancel()
        poll = nil
        detector.reset()
        if active != nil {
            Task { await finish(reason: .userStopped) }
        }
    }

    func settingsChanged() {
        if settings.isEnabled { start() } else { stop() }
    }

    /// One poll. Internal so a test can drive it with a fixture source.
    func tick(now: Date) {
        detector.doNotRecord = MeetingRuleList.parse(settings.doNotRecordText)
        for event in detector.ingest(source.snapshot(at: now)) {
            switch event {
            case let .meetingStarted(context):
                begin(context)
            case let .meetingEnded(_, reason):
                Task { await finish(reason: reason) }
            case let .meetingSkipped(context, matched):
                Self.logger.notice("meeting skipped by do-not-record entry")
                onNotice?(LanguageManager.shared.t("meeting.notice.skipped", context.title, matched))
            }
        }
    }

    // MARK: Person's controls

    /// 止める — keep what was recorded and hand it off now.
    func stopRecording() {
        guard active != nil else { return }
        detector.dismissActive(at: .now)
        Task { await finish(reason: .userStopped) }
    }

    /// 捨てる — stop and delete everything from this meeting.
    func discardRecording() {
        guard let recording = active else { return }
        active = nil
        detector.dismissActive(at: .now)
        phase = .idle
        Task {
            _ = await recording.startTask.value
            _ = await recording.recorder.stop()
            try? FileManager.default.removeItem(at: recording.directory)
            Self.logger.notice("meeting discarded")
        }
        onNotice?(LanguageManager.shared.t("meeting.notice.discarded"))
    }

    /// Closes the summary card.
    func dismissSummary() {
        if case .summaryReady = phase { phase = .idle }
    }

    // MARK: Recording

    private func begin(_ context: MeetingContext) {
        guard active == nil else { return }
        var layout = MeetingRecordingLayout(startedAt: context.startedAt)
        var directory = layout.directory(in: recordingsRoot)
        var suffix = 2
        while FileManager.default.fileExists(atPath: directory.path) {
            layout = MeetingRecordingLayout(id: "\(MeetingRecordingLayout.id(for: context.startedAt))-\(suffix)")
            directory = layout.directory(in: recordingsRoot)
            suffix += 1
        }
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
            )
        } catch {
            Self.logger.error("meeting folder failed: \(error.localizedDescription, privacy: .public)")
            detector.dismissActive(at: .now)
            return
        }

        let recorder = makeRecorder()
        let micURL = directory.appendingPathComponent(layout.micFileName)
        let systemURL = directory.appendingPathComponent(layout.systemFileName)
        let startTask = Task { @MainActor () -> Bool in
            do {
                try await recorder.start(context: context, micURL: micURL, systemURL: systemURL)
                return true
            } catch {
                return false
            }
        }
        active = ActiveRecording(layout: layout, directory: directory, context: context, recorder: recorder, startTask: startTask)
        phase = .recording(id: layout.id, title: context.title, startedAt: context.startedAt)
        // A summary still on screen from the last meeting gives way.
        summaryWatch?.cancel()
        summaryWatch = nil
        onNotice?(LanguageManager.shared.t("meeting.notice.started", context.title))
        Self.logger.notice("meeting recording started source=\(context.source.rawValue, privacy: .public)")

        Task { @MainActor [weak self] in
            guard await startTask.value == false, let self, self.active?.layout == layout else { return }
            // Neither channel could start (permissions refused).
            self.active = nil
            self.phase = .idle
            self.detector.dismissActive(at: .now)
            try? FileManager.default.removeItem(at: directory)
            self.onNotice?(LanguageManager.shared.t("meeting.notice.failed"))
        }
    }

    private func finish(reason: MeetingEndReason) async {
        guard let recording = active else { return }
        active = nil
        _ = await recording.startTask.value
        let result = await recording.recorder.stop()
        let endedAt = Date()
        let scope = MeetingScope.classify(
            recording.context,
            keywords: MeetingRuleList.parse(settings.companyKeywordsText),
            domains: MeetingRuleList.parse(settings.companyDomainsText)
        )
        let manifest = MeetingManifest(
            id: recording.layout.id,
            context: recording.context,
            endedAt: endedAt,
            endReason: reason,
            scope: scope,
            files: .init(
                mic: result.micRecorded ? recording.layout.micFileName : nil,
                sys: result.systemRecorded ? recording.layout.systemFileName : nil
            ),
            recordingDir: recording.directory.path
        )
        let directory = recording.directory
        let inbox = inboxURL
        do {
            _ = try await Task.detached {
                try MeetingInbox.deliver(manifest: manifest, from: directory, to: inbox)
            }.value
        } catch MeetingInbox.DeliveryError.nothingRecorded {
            try? FileManager.default.removeItem(at: directory)
            if case .recording = phase { phase = .idle }
            return
        } catch {
            Self.logger.error("meeting hand-off failed: \(error.localizedDescription, privacy: .public)")
            // Keep the files where they are; the manifest says what they are.
            if let data = try? MeetingManifest.encoder().encode(manifest) {
                try? data.write(to: directory.appendingPathComponent(MeetingRecordingLayout.manifestFileName))
            }
            if case .recording = phase { phase = .idle }
            onNotice?(LanguageManager.shared.t("meeting.notice.handoffFailed"))
            return
        }

        Self.logger.notice("meeting handed off reason=\(reason.rawValue, privacy: .public)")
        // Another meeting may already be recording; don't overwrite its state.
        if active == nil {
            phase = .processing(id: manifest.id, title: manifest.title, endedAt: endedAt)
        }
        onNotice?(LanguageManager.shared.t("meeting.notice.processing", manifest.title))
        watchForSummary(id: manifest.id, title: manifest.title, directory: directory, endedAt: endedAt)
    }

    private func watchForSummary(id: String, title: String, directory: URL, endedAt: Date) {
        summaryWatch?.cancel()
        summaryWatch = Task { @MainActor [weak self] in
            while !Task.isCancelled, MeetingSummaryWatch.shouldKeepWaiting(endedAt: endedAt, now: .now) {
                if let summary = MeetingSummary.load(from: directory) {
                    guard let self else { return }
                    if self.active == nil {
                        self.phase = .summaryReady(id: id, title: summary.title ?? title, summary: summary)
                        self.onNotice?(LanguageManager.shared.t("meeting.notice.summaryReady", summary.title ?? title))
                    }
                    return
                }
                do { try await Task.sleep(for: .seconds(MeetingSummaryWatch.pollInterval)) } catch { return }
            }
            guard let self, case .processing(let current, _, _) = self.phase, current == id else { return }
            self.phase = .idle
        }
    }
}
