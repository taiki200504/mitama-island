import Foundation

/// What the platform layer sees at one moment, as plain values.
///
/// Nothing here is a CoreAudio, AppKit or EventKit type — `OpenIslandApp`
/// reads those and fills this in, so every rule about "is this a meeting" can
/// be checked by a test on any machine.
public struct MeetingSignals: Equatable, Sendable {
    public struct RunningApp: Equatable, Sendable {
        public let bundleID: String?
        public let name: String

        public init(bundleID: String?, name: String) {
            self.bundleID = bundleID
            self.name = name
        }
    }

    /// A window title together with the app that owns it. Only browser windows
    /// are interesting, but the owner is what the recorder captures audio from.
    public struct WindowTitle: Equatable, Sendable {
        public let ownerBundleID: String?
        public let ownerName: String
        public let title: String

        public init(ownerBundleID: String?, ownerName: String, title: String) {
            self.ownerBundleID = ownerBundleID
            self.ownerName = ownerName
            self.title = title
        }
    }

    /// The microphone is open in some process other than this app. The island's
    /// own engines (earshot, the meeting recorder) must already be excluded —
    /// otherwise recording would keep itself alive forever.
    public var micInUse: Bool
    /// Bundle IDs of the processes holding the microphone, when the OS says
    /// (macOS 14.4+). Empty means "unknown", not "nobody".
    public var micClients: [String]
    public var runningApps: [RunningApp]
    public var windowTitles: [WindowTitle]
    public var calendarNow: MeetingCalendarEntry?
    public var at: Date

    public init(
        micInUse: Bool,
        micClients: [String] = [],
        runningApps: [RunningApp] = [],
        windowTitles: [WindowTitle] = [],
        calendarNow: MeetingCalendarEntry? = nil,
        at: Date
    ) {
        self.micInUse = micInUse
        self.micClients = micClients
        self.runningApps = runningApps
        self.windowTitles = windowTitles
        self.calendarNow = calendarNow
        self.at = at
    }
}

/// The calendar entry happening right now, if any. Attendees and calendar name
/// are optional because the island's calendar layer does not read them yet;
/// the company/personal tagging uses them when present.
public struct MeetingCalendarEntry: Equatable, Codable, Sendable {
    public var title: String
    public var startsAt: Date
    public var endsAt: Date
    public var url: URL?
    public var attendees: [String]
    public var calendarName: String?

    public init(
        title: String,
        startsAt: Date,
        endsAt: Date,
        url: URL? = nil,
        attendees: [String] = [],
        calendarName: String? = nil
    ) {
        self.title = title
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.url = url
        self.attendees = attendees
        self.calendarName = calendarName
    }

    enum CodingKeys: String, CodingKey {
        case title
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case url
        case attendees
        case calendarName = "calendar_name"
    }
}

/// Which signal made the detector call it a meeting.
public enum MeetingSource: String, Codable, Sendable {
    /// A native meeting app (Zoom, Teams, FaceTime …).
    case app
    /// A browser window whose title reads like Meet / Zoom / Teams.
    case browser
    /// Only the calendar said so. The recorder then takes all system audio.
    case calendar
}

/// Why a meeting stopped being recorded.
public enum MeetingEndReason: String, Codable, Sendable {
    case micIdle = "mic_idle"
    case appClosed = "app_closed"
    case userStopped = "user_stopped"
}

/// The meeting as the detector understood it when it started.
public struct MeetingContext: Equatable, Codable, Sendable {
    public var source: MeetingSource
    /// The app whose audio is "the other side". `nil` means no single app is
    /// known (calendar-only), and the recorder takes all system audio.
    public var appBundleID: String?
    public var appName: String
    public var title: String
    public var calendar: MeetingCalendarEntry?
    public var startedAt: Date

    public init(
        source: MeetingSource,
        appBundleID: String?,
        appName: String,
        title: String,
        calendar: MeetingCalendarEntry?,
        startedAt: Date
    ) {
        self.source = source
        self.appBundleID = appBundleID
        self.appName = appName
        self.title = title
        self.calendar = calendar
        self.startedAt = startedAt
    }
}

public enum MeetingDetectorEvent: Equatable, Sendable {
    case meetingStarted(MeetingContext)
    case meetingEnded(MeetingContext, reason: MeetingEndReason)
    /// A meeting was seen but the do-not-record list matched. Emitted once per
    /// meeting so the island can say so; nothing is recorded.
    case meetingSkipped(MeetingContext, matched: String)
}

/// A native meeting app, recognised by bundle ID or process name.
public struct KnownMeetingApp: Equatable, Sendable {
    public let displayName: String
    public let bundleIDs: Set<String>
    public let processNames: Set<String>
    /// Apps that sit in the menu bar all day (Slack, Discord) only count when
    /// they are the ones holding the microphone — if the OS can say who is.
    public let requiresMicOwnership: Bool

    public init(displayName: String, bundleIDs: Set<String>, processNames: Set<String>, requiresMicOwnership: Bool = false) {
        self.displayName = displayName
        self.bundleIDs = bundleIDs
        self.processNames = processNames
        self.requiresMicOwnership = requiresMicOwnership
    }

    func matches(_ app: MeetingSignals.RunningApp) -> Bool {
        if let id = app.bundleID, bundleIDs.contains(id) { return true }
        return processNames.contains(app.name)
    }
}

/// Decides when a meeting starts and ends from a stream of `MeetingSignals`.
///
/// Start: the microphone is in use AND one of
/// - a known meeting app is running (and, when the OS says who holds the mic,
///   it is that app),
/// - a browser window title reads like Meet / Zoom / Teams / Webex,
/// - the calendar has a meeting right now.
///
/// End: the microphone has been idle for `micIdleGrace` (60 s), or the app the
/// meeting started in has quit.
///
/// The do-not-record list is checked once, at start. A meeting it matches is
/// held as "suppressed" until it ends, so it is not re-evaluated every tick and
/// does not start recording halfway through.
public struct MeetingDetector: Sendable {
    public static let defaultMicIdleGrace: TimeInterval = 60

    public static let knownApps: [KnownMeetingApp] = [
        KnownMeetingApp(displayName: "Zoom", bundleIDs: ["us.zoom.xos"], processNames: ["zoom.us"]),
        KnownMeetingApp(
            displayName: "Microsoft Teams",
            bundleIDs: ["com.microsoft.teams", "com.microsoft.teams2"],
            processNames: ["Microsoft Teams", "Microsoft Teams (work or school)", "MSTeams"]
        ),
        KnownMeetingApp(displayName: "FaceTime", bundleIDs: ["com.apple.FaceTime"], processNames: ["FaceTime"]),
        KnownMeetingApp(
            displayName: "Webex",
            bundleIDs: ["com.cisco.webexmeetingsapp", "com.webex.meetingmanager", "Cisco-Systems.Spark"],
            processNames: ["Webex", "Cisco Webex Meetings"]
        ),
        KnownMeetingApp(
            displayName: "Slack",
            bundleIDs: ["com.tinyspeck.slackmacgap"],
            processNames: ["Slack"],
            requiresMicOwnership: true
        ),
        KnownMeetingApp(
            displayName: "Discord",
            bundleIDs: ["com.hnc.Discord"],
            processNames: ["Discord"],
            requiresMicOwnership: true
        ),
        KnownMeetingApp(displayName: "Around", bundleIDs: ["co.teamport.around"], processNames: ["Around"]),
        KnownMeetingApp(displayName: "Tuple", bundleIDs: ["app.tuple.app"], processNames: ["Tuple"]),
    ]

    /// Browsers whose window titles are read for in-browser meetings.
    public static let browserBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.apple.Safari",
        "company.thebrowser.Browser",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "com.brave.Browser",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "com.mitama.browser",
    ]

    /// Patterns a browser tab title takes while a call is open. Deliberately
    /// narrower than "contains Zoom": a doc called "Zoom pricing" is not a call.
    private static let browserTitlePatterns: [NSRegularExpression] = [
        #"^Meet\s*[-–—:|]"#,
        #"\bGoogle Meet\b"#,
        #"meet\.google\.com"#,
        #"\bZoom (Meeting|Webinar|Workplace)\b"#,
        #"zoom\.us/(j|wc|s)/"#,
        #"\bMicrosoft Teams\b"#,
        #"teams\.(microsoft|live)\.com"#,
        #"\bWebex\b"#,
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    public static func titleLooksLikeMeeting(_ title: String) -> Bool {
        let range = NSRange(title.startIndex..<title.endIndex, in: title)
        return browserTitlePatterns.contains { $0.firstMatch(in: title, range: range) != nil }
    }

    private enum State: Equatable, Sendable {
        case idle
        case active(MeetingContext, lastMicAt: Date)
        /// A meeting is going on but is not being recorded — skipped by the
        /// do-not-record list, or stopped by the person.
        case suppressed(MeetingContext, lastMicAt: Date)
    }

    public var micIdleGrace: TimeInterval
    public var doNotRecord: [String]
    private var state: State = .idle

    public init(micIdleGrace: TimeInterval = MeetingDetector.defaultMicIdleGrace, doNotRecord: [String] = []) {
        self.micIdleGrace = micIdleGrace
        self.doNotRecord = doNotRecord
    }

    /// The meeting being recorded right now, if any.
    public var activeMeeting: MeetingContext? {
        if case let .active(context, _) = state { return context }
        return nil
    }

    public var isSuppressed: Bool {
        if case .suppressed = state { return true }
        return false
    }

    /// Feeds one snapshot and returns what changed.
    public mutating func ingest(_ signals: MeetingSignals) -> [MeetingDetectorEvent] {
        switch state {
        case .idle:
            guard signals.micInUse, let context = Self.candidate(in: signals) else { return [] }
            if let matched = MeetingExclusion.match(context, against: doNotRecord) {
                state = .suppressed(context, lastMicAt: signals.at)
                return [.meetingSkipped(context, matched: matched)]
            }
            state = .active(context, lastMicAt: signals.at)
            return [.meetingStarted(context)]

        case let .active(context, lastMicAt):
            if let reason = endReason(context, lastMicAt: lastMicAt, signals: signals) {
                state = .idle
                return [.meetingEnded(context, reason: reason)]
            }
            state = .active(context, lastMicAt: signals.micInUse ? signals.at : lastMicAt)
            return []

        case let .suppressed(context, lastMicAt):
            if endReason(context, lastMicAt: lastMicAt, signals: signals) != nil {
                state = .idle
            } else {
                state = .suppressed(context, lastMicAt: signals.micInUse ? signals.at : lastMicAt)
            }
            return []
        }
    }

    /// The person pressed stop or discard. The meeting is not picked up again
    /// until it actually ends. Returns the meeting that was active, if any.
    @discardableResult
    public mutating func dismissActive(at moment: Date) -> MeetingContext? {
        guard case let .active(context, lastMicAt) = state else { return nil }
        state = .suppressed(context, lastMicAt: max(lastMicAt, moment))
        return context
    }

    /// Forget everything — used when the feature is switched off.
    public mutating func reset() {
        state = .idle
    }

    private func endReason(_ context: MeetingContext, lastMicAt: Date, signals: MeetingSignals) -> MeetingEndReason? {
        if Self.appHasQuit(context, signals: signals) { return .appClosed }
        if !signals.micInUse, signals.at.timeIntervalSince(lastMicAt) >= micIdleGrace { return .micIdle }
        return nil
    }

    private static func appHasQuit(_ context: MeetingContext, signals: MeetingSignals) -> Bool {
        // Calendar-only meetings have no app to quit.
        guard context.source != .calendar else { return false }
        return !signals.runningApps.contains { app in
            if let id = context.appBundleID, let appID = app.bundleID { return appID == id }
            return app.name == context.appName
        }
    }

    private static func clientMatches(_ clients: [String], bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        // Helpers carry the parent's ID as a prefix (com.google.Chrome.helper).
        return clients.contains { $0 == bundleID || $0.hasPrefix(bundleID + ".") }
    }

    /// The meeting these signals describe, assuming the mic is in use.
    static func candidate(in signals: MeetingSignals) -> MeetingContext? {
        let clientsKnown = !signals.micClients.isEmpty
        let calendar = signals.calendarNow

        // 1. A native meeting app. When the OS says who holds the mic, the app
        //    has to be one of them — Zoom left open after a call is not a call.
        for app in signals.runningApps {
            guard let known = knownApps.first(where: { $0.matches(app) }) else { continue }
            if clientsKnown {
                guard clientMatches(signals.micClients, bundleID: app.bundleID) else { continue }
            } else if known.requiresMicOwnership {
                // Without ownership info, Slack/Discord would make every
                // dictation a "meeting" — they still count, per the spec, but
                // only when nothing better (a calendar entry) is around.
                if calendar == nil {
                    return context(.app, app: app, displayName: known.displayName, title: nil, calendar: nil, at: signals.at)
                }
                continue
            }
            return context(.app, app: app, displayName: known.displayName, title: nil, calendar: calendar, at: signals.at)
        }

        // 2. A browser tab that reads like a call.
        for window in signals.windowTitles where titleLooksLikeMeeting(window.title) {
            if let id = window.ownerBundleID, !browserBundleIDs.contains(id) { continue }
            if clientsKnown, !clientMatches(signals.micClients, bundleID: window.ownerBundleID) { continue }
            let app = MeetingSignals.RunningApp(bundleID: window.ownerBundleID, name: window.ownerName)
            return context(.browser, app: app, displayName: window.ownerName, title: window.title, calendar: calendar, at: signals.at)
        }

        // 3. The calendar alone.
        if let calendar {
            return MeetingContext(
                source: .calendar,
                appBundleID: nil,
                appName: "Calendar",
                title: calendar.title,
                calendar: calendar,
                startedAt: signals.at
            )
        }
        return nil
    }

    private static func context(
        _ source: MeetingSource,
        app: MeetingSignals.RunningApp,
        displayName: String,
        title: String?,
        calendar: MeetingCalendarEntry?,
        at: Date
    ) -> MeetingContext {
        MeetingContext(
            source: source,
            appBundleID: app.bundleID,
            appName: app.name,
            // The calendar's name for a meeting beats a tab title, which beats
            // the app's name.
            title: calendar?.title ?? title ?? displayName,
            calendar: calendar,
            startedAt: at
        )
    }
}

/// The person's "do not record" list.
///
/// Entries are free text, one per line. An entry matches when it appears
/// (case-insensitively) in the meeting's app bundle ID, app name, title,
/// calendar title or any attendee address. `@example.com` therefore excludes
/// everyone from that domain, and `FaceTime` excludes the app.
public enum MeetingExclusion {
    public static func match(_ context: MeetingContext, against entries: [String]) -> String? {
        var fields: [String] = [context.appName, context.title]
        if let id = context.appBundleID { fields.append(id) }
        if let calendar = context.calendar {
            fields.append(calendar.title)
            fields.append(contentsOf: calendar.attendees)
            if let name = calendar.calendarName { fields.append(name) }
        }
        let haystack = fields.map { $0.lowercased() }
        for entry in entries {
            let needle = entry.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !needle.isEmpty else { continue }
            if haystack.contains(where: { $0.contains(needle) }) { return entry.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return nil
    }
}

/// Splits an editable text field into list entries: one per line or comma,
/// trimmed, blank lines and `#` comments dropped.
public enum MeetingRuleList {
    public static func parse(_ text: String) -> [String] {
        text
            .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == "\r" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }
}

/// Personal or company. Company meetings are still recorded; the tag tells the
/// mitama-os pickup to send the notes to the company side instead of the
/// personal Hub (24-meeting-autocapture §3.5).
public enum MeetingScope: String, Codable, Sendable {
    case personal
    case company

    /// `keywords` match the title, calendar title or calendar name;
    /// `domains` match attendee addresses (`gugen.co.jp` or `@gugen.co.jp`).
    public static func classify(_ context: MeetingContext, keywords: [String], domains: [String]) -> MeetingScope {
        var texts = [context.title]
        if let calendar = context.calendar {
            texts.append(calendar.title)
            if let name = calendar.calendarName { texts.append(name) }
        }
        let lowered = texts.map { $0.lowercased() }
        for keyword in keywords {
            let needle = keyword.trimmingCharacters(in: .whitespaces).lowercased()
            if !needle.isEmpty, lowered.contains(where: { $0.contains(needle) }) { return .company }
        }
        let attendees = context.calendar?.attendees.map { $0.lowercased() } ?? []
        for domain in domains {
            var needle = domain.trimmingCharacters(in: .whitespaces).lowercased()
            if needle.hasPrefix("@") { needle.removeFirst() }
            guard !needle.isEmpty else { continue }
            if attendees.contains(where: { $0.hasSuffix("@" + needle) || $0.hasSuffix("." + needle) }) {
                return .company
            }
        }
        return .personal
    }
}
