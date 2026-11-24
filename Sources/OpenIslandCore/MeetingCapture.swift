import Foundation

/// Where a meeting recording lives and what its files are called.
///
/// One folder per meeting, named by its local start time:
///
///     ~/Library/Application Support/mitama/meetings/<id>/
///         <id>.mic.m4a     the microphone — this person
///         <id>.sys.m4a     the meeting app's audio — everyone else
///         manifest.json    written when the meeting ends
///         summary.json     written later by mitama-os
///
/// The audio moves to the mitama inbox at hand-off; the manifest stays here,
/// and `summary.json` appears here when mitama-os is done.
public struct MeetingRecordingLayout: Equatable, Sendable {
    public static let manifestFileName = "manifest.json"
    public static let summaryFileName = "summary.json"

    public let id: String

    public init(id: String) {
        self.id = id
    }

    public init(startedAt: Date, timeZone: TimeZone = .current) {
        self.id = Self.id(for: startedAt, timeZone: timeZone)
    }

    /// `20261124-153000` — sortable, no characters a shell or a file system
    /// will argue with.
    public static func id(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    public var micFileName: String { "\(id).mic.m4a" }
    public var systemFileName: String { "\(id).sys.m4a" }

    public func directory(in root: URL) -> URL {
        root.appendingPathComponent(id, isDirectory: true)
    }

    public static func defaultRecordingsRoot(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/mitama/meetings", isDirectory: true)
    }

    public static func defaultInbox(home: URL) -> URL {
        home.appendingPathComponent(".mitama/meetings/inbox", isDirectory: true)
    }

    /// Expands a leading `~` in a path typed into Settings.
    public static func expandTilde(_ path: String, home: URL) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return defaultInbox(home: home) }
        if trimmed == "~" { return home }
        if trimmed.hasPrefix("~/") {
            return home.appendingPathComponent(String(trimmed.dropFirst(2)), isDirectory: true)
        }
        return URL(fileURLWithPath: trimmed, isDirectory: true)
    }
}

/// The hand-off contract with mitama-os. Field names are snake_case and the
/// schema string is versioned; mitama-os rejects schemas it does not know.
public struct MeetingManifest: Equatable, Codable, Sendable {
    public static let currentSchema = "mitama.meeting.v1"

    public struct App: Equatable, Codable, Sendable {
        public var bundleID: String?
        public var name: String

        public init(bundleID: String?, name: String) {
            self.bundleID = bundleID
            self.name = name
        }

        enum CodingKeys: String, CodingKey {
            case bundleID = "bundle_id"
            case name
        }
    }

    /// File names relative to the folder the manifest sits in. `nil` when that
    /// channel recorded nothing (screen-recording permission refused, say).
    public struct Files: Equatable, Codable, Sendable {
        public var mic: String?
        public var sys: String?

        public init(mic: String?, sys: String?) {
            self.mic = mic
            self.sys = sys
        }
    }

    public var schema: String
    public var id: String
    public var startedAt: Date
    public var endedAt: Date
    public var durationSeconds: Double
    public var source: MeetingSource
    public var app: App
    public var title: String
    public var scope: MeetingScope
    public var calendar: MeetingCalendarEntry?
    public var endReason: MeetingEndReason
    public var files: Files
    /// Which channel is who: `mic` is this person, `sys` is everyone else.
    public var channels: [String: String]
    /// Always true — a meeting has other people in it. mitama-os applies its
    /// third-party retention (`.3p.`: audio 1 h, text 7 d).
    public var thirdParty: Bool
    /// Absolute path of the island's folder for this meeting. mitama-os writes
    /// `summary.json` here when the notes are done.
    public var recordingDir: String
    public var createdBy: String

    public init(
        id: String,
        context: MeetingContext,
        endedAt: Date,
        endReason: MeetingEndReason,
        scope: MeetingScope,
        files: Files,
        recordingDir: String
    ) {
        self.schema = Self.currentSchema
        self.id = id
        self.startedAt = context.startedAt
        self.endedAt = endedAt
        self.durationSeconds = max(0, endedAt.timeIntervalSince(context.startedAt))
        self.source = context.source
        self.app = App(bundleID: context.appBundleID, name: context.appName)
        self.title = context.title
        self.scope = scope
        self.calendar = context.calendar
        self.endReason = endReason
        self.files = files
        self.channels = ["mic": "self", "sys": "others"]
        self.thirdParty = true
        self.recordingDir = recordingDir
        self.createdBy = "mitama-island"
    }

    enum CodingKeys: String, CodingKey {
        case schema, id, source, app, title, scope, calendar, files, channels
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationSeconds = "duration_seconds"
        case endReason = "end_reason"
        case thirdParty = "third_party"
        case recordingDir = "recording_dir"
        case createdBy = "created_by"
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Moves a finished recording into the folder mitama-os picks up from.
///
/// The inbox only ever sees complete meetings: everything is assembled in a
/// hidden `.<id>.partial` folder and renamed into place in one step, and the
/// manifest is the last file written. A pickup script should ignore names that
/// start with a dot and folders without `manifest.json`.
public enum MeetingInbox {
    public enum DeliveryError: Error, Equatable {
        case nothingRecorded
    }

    /// Returns the delivered folder (`<inbox>/<id>/`).
    @discardableResult
    public static func deliver(
        manifest: MeetingManifest,
        from recordingDirectory: URL,
        to inbox: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let audio = [manifest.files.mic, manifest.files.sys].compactMap { $0 }
            .filter { fileManager.fileExists(atPath: recordingDirectory.appendingPathComponent($0).path) }
        guard !audio.isEmpty else { throw DeliveryError.nothingRecorded }

        try fileManager.createDirectory(at: inbox, withIntermediateDirectories: true)
        let staging = inbox.appendingPathComponent(".\(manifest.id).partial", isDirectory: true)
        if fileManager.fileExists(atPath: staging.path) {
            try fileManager.removeItem(at: staging)
        }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

        // Move, not copy: the audio of a meeting with other people in it
        // should exist in one place, under mitama-os's retention rules.
        for name in audio {
            let source = recordingDirectory.appendingPathComponent(name)
            let destination = staging.appendingPathComponent(name)
            do {
                try fileManager.moveItem(at: source, to: destination)
            } catch {
                try fileManager.copyItem(at: source, to: destination)
                try? fileManager.removeItem(at: source)
            }
        }

        var delivered = manifest
        delivered.files = MeetingManifest.Files(
            mic: manifest.files.mic.flatMap { audio.contains($0) ? $0 : nil },
            sys: manifest.files.sys.flatMap { audio.contains($0) ? $0 : nil }
        )
        let data = try MeetingManifest.encoder().encode(delivered)
        try data.write(to: staging.appendingPathComponent(MeetingRecordingLayout.manifestFileName), options: .atomic)
        // The island keeps its own copy, so the summary view knows the title.
        try data.write(to: recordingDirectory.appendingPathComponent(MeetingRecordingLayout.manifestFileName), options: .atomic)

        var final = inbox.appendingPathComponent(manifest.id, isDirectory: true)
        var suffix = 2
        while fileManager.fileExists(atPath: final.path) {
            final = inbox.appendingPathComponent("\(manifest.id)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        try fileManager.moveItem(at: staging, to: final)
        return final
    }
}

/// What mitama-os writes to `<recording_dir>/summary.json` once the notes are
/// made. Every list is optional; only `summary` is required.
public struct MeetingSummary: Equatable, Codable, Sendable {
    public static let currentSchema = "mitama.meeting.summary.v1"

    public var schema: String?
    public var id: String?
    public var title: String?
    public var summary: String
    public var decisions: [String]
    public var myTasks: [String]
    public var aiRequests: [String]
    public var othersTasks: [String]
    public var ideas: [String]
    /// Where the full notes and the "決める" card live, if mitama-os has a URL.
    public var hubURL: String?
    /// Left as text: mitama-os writes JavaScript ISO strings with milliseconds,
    /// which `JSONDecoder.iso8601` refuses.
    public var generatedAt: String?

    public init(
        summary: String,
        title: String? = nil,
        decisions: [String] = [],
        myTasks: [String] = [],
        aiRequests: [String] = [],
        othersTasks: [String] = [],
        ideas: [String] = [],
        hubURL: String? = nil
    ) {
        self.schema = Self.currentSchema
        self.id = nil
        self.title = title
        self.summary = summary
        self.decisions = decisions
        self.myTasks = myTasks
        self.aiRequests = aiRequests
        self.othersTasks = othersTasks
        self.ideas = ideas
        self.hubURL = hubURL
        self.generatedAt = nil
    }

    enum CodingKeys: String, CodingKey {
        case schema, id, title, summary, decisions, ideas
        case myTasks = "my_tasks"
        case aiRequests = "ai_requests"
        case othersTasks = "others_tasks"
        case hubURL = "hub_url"
        case generatedAt = "generated_at"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decodeIfPresent(String.self, forKey: .schema)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        summary = try container.decode(String.self, forKey: .summary)
        decisions = try container.decodeIfPresent([String].self, forKey: .decisions) ?? []
        myTasks = try container.decodeIfPresent([String].self, forKey: .myTasks) ?? []
        aiRequests = try container.decodeIfPresent([String].self, forKey: .aiRequests) ?? []
        othersTasks = try container.decodeIfPresent([String].self, forKey: .othersTasks) ?? []
        ideas = try container.decodeIfPresent([String].self, forKey: .ideas) ?? []
        hubURL = try container.decodeIfPresent(String.self, forKey: .hubURL)
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt)
    }

    /// Reads `summary.json` from a recording folder. `nil` while it is not
    /// there yet or is half-written.
    public static func load(from recordingDirectory: URL) -> MeetingSummary? {
        let url = recordingDirectory.appendingPathComponent(MeetingRecordingLayout.summaryFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MeetingSummary.self, from: data)
    }

    /// The one line the island shows: the counts that matter.
    public var countsLine: String {
        var parts: [String] = []
        if !decisions.isEmpty { parts.append("決定 \(decisions.count)") }
        if !myTasks.isEmpty { parts.append("タスク \(myTasks.count)") }
        if !aiRequests.isEmpty { parts.append("依頼 \(aiRequests.count)") }
        return parts.joined(separator: " · ")
    }
}

/// What the island shows about meeting capture.
public enum MeetingCapturePhase: Equatable, Sendable {
    case idle
    case recording(id: String, title: String, startedAt: Date)
    /// Handed to mitama-os; the notes are being made.
    case processing(id: String, title: String, endedAt: Date)
    case summaryReady(id: String, title: String, summary: MeetingSummary)

    public var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    /// Whole minutes recorded so far, for the closed island. Never negative.
    public func recordingMinutes(at now: Date) -> Int? {
        guard case let .recording(_, _, startedAt) = self else { return nil }
        return max(0, Int(now.timeIntervalSince(startedAt) / 60))
    }

    /// `12:05` for the opened island.
    public static func elapsedText(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }
}

/// How long the island keeps asking for a summary after a meeting ends.
public enum MeetingSummaryWatch {
    public static let pollInterval: TimeInterval = 15
    public static let giveUpAfter: TimeInterval = 2 * 60 * 60

    public static func shouldKeepWaiting(endedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(endedAt) < giveUpAfter
    }
}
