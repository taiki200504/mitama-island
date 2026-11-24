import Foundation
import Testing
@testable import OpenIslandCore

@Suite struct MeetingDetectorTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let zoom = MeetingSignals.RunningApp(bundleID: "us.zoom.xos", name: "zoom.us")
    private let slack = MeetingSignals.RunningApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")
    private let chrome = MeetingSignals.RunningApp(bundleID: "com.google.Chrome", name: "Google Chrome")

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private func started(_ events: [MeetingDetectorEvent]) -> MeetingContext? {
        for event in events { if case let .meetingStarted(context) = event { return context } }
        return nil
    }

    @Test("Mic in use with Zoom running starts a meeting in Zoom")
    func zoomStarts() {
        var detector = MeetingDetector()
        let events = detector.ingest(MeetingSignals(micInUse: true, runningApps: [zoom], at: t0))
        let context = started(events)
        #expect(context?.source == .app)
        #expect(context?.appBundleID == "us.zoom.xos")
        #expect(context?.title == "Zoom")
        #expect(detector.activeMeeting != nil)
    }

    @Test("A meeting app with the mic idle is not a meeting")
    func appWithoutMic() {
        var detector = MeetingDetector()
        #expect(detector.ingest(MeetingSignals(micInUse: false, runningApps: [zoom], at: t0)).isEmpty)
        #expect(detector.activeMeeting == nil)
    }

    @Test("Mic in use with nothing meeting-like is not a meeting")
    func micAlone() {
        var detector = MeetingDetector()
        #expect(detector.ingest(MeetingSignals(micInUse: true, runningApps: [chrome], at: t0)).isEmpty)
    }

    @Test("Known mic clients: Zoom left open does not count when someone else holds the mic")
    func zoomIdleWhileOtherAppUsesMic() {
        var detector = MeetingDetector()
        let signals = MeetingSignals(micInUse: true, micClients: ["com.apple.VoiceMemos"], runningApps: [zoom], at: t0)
        #expect(detector.ingest(signals).isEmpty)
    }

    @Test("Known mic clients: a helper process counts for its parent app")
    func helperCountsForParent() {
        var detector = MeetingDetector()
        let window = MeetingSignals.WindowTitle(ownerBundleID: "com.google.Chrome", ownerName: "Google Chrome", title: "Meet - abc-defg-hij")
        let signals = MeetingSignals(
            micInUse: true, micClients: ["com.google.Chrome.helper"], runningApps: [chrome], windowTitles: [window], at: t0
        )
        let context = started(detector.ingest(signals))
        #expect(context?.source == .browser)
        #expect(context?.appBundleID == "com.google.Chrome")
        #expect(context?.title == "Meet - abc-defg-hij")
    }

    @Test("Slack only counts as a huddle when it holds the mic, if that is known")
    func slackNeedsMic() {
        var detector = MeetingDetector()
        #expect(detector.ingest(MeetingSignals(micInUse: true, micClients: ["com.apple.Siri"], runningApps: [slack], at: t0)).isEmpty)
        var other = MeetingDetector()
        let context = started(other.ingest(MeetingSignals(micInUse: true, micClients: ["com.tinyspeck.slackmacgap"], runningApps: [slack], at: t0)))
        #expect(context?.title == "Slack")
    }

    @Test(
        "Browser titles that read like a call",
        arguments: [
            "Meet - abc-defg-hij",
            "Meet – Weekly sync",
            "Weekly sync - Google Meet",
            "Zoom Meeting",
            "Meeting with Sato | Microsoft Teams",
            "https://us02web.zoom.us/j/12345",
            "Cisco Webex",
        ]
    )
    func meetingTitles(title: String) {
        #expect(MeetingDetector.titleLooksLikeMeeting(title))
    }

    @Test(
        "Browser titles that are not calls",
        arguments: ["Zoom pricing - Google Search", "Meeting notes.docx", "GitHub", "Meetup events"]
    )
    func nonMeetingTitles(title: String) {
        #expect(!MeetingDetector.titleLooksLikeMeeting(title))
    }

    @Test("A meeting-like title in a non-browser app is ignored")
    func titleOutsideBrowser() {
        var detector = MeetingDetector()
        let window = MeetingSignals.WindowTitle(ownerBundleID: "com.apple.TextEdit", ownerName: "TextEdit", title: "Zoom Meeting")
        #expect(detector.ingest(MeetingSignals(micInUse: true, windowTitles: [window], at: t0)).isEmpty)
    }

    @Test("Calendar meeting now plus mic starts a calendar meeting, titled by the calendar")
    func calendarStarts() {
        var detector = MeetingDetector()
        let entry = MeetingCalendarEntry(title: "1on1 with Tanaka", startsAt: at(-60), endsAt: at(1800))
        let context = started(detector.ingest(MeetingSignals(micInUse: true, calendarNow: entry, at: t0)))
        #expect(context?.source == .calendar)
        #expect(context?.appBundleID == nil)
        #expect(context?.title == "1on1 with Tanaka")
    }

    @Test("The calendar title wins over the app name")
    func calendarTitleWins() {
        var detector = MeetingDetector()
        let entry = MeetingCalendarEntry(title: "Design review", startsAt: at(-60), endsAt: at(1800))
        let context = started(detector.ingest(MeetingSignals(micInUse: true, runningApps: [zoom], calendarNow: entry, at: t0)))
        #expect(context?.source == .app)
        #expect(context?.title == "Design review")
    }

    @Test("Mic idle for less than 60 s keeps the meeting; 60 s ends it")
    func micIdleGrace() {
        var detector = MeetingDetector()
        _ = detector.ingest(MeetingSignals(micInUse: true, runningApps: [zoom], at: t0))
        _ = detector.ingest(MeetingSignals(micInUse: true, runningApps: [zoom], at: at(30)))
        #expect(detector.ingest(MeetingSignals(micInUse: false, runningApps: [zoom], at: at(60))).isEmpty)
        #expect(detector.ingest(MeetingSignals(micInUse: false, runningApps: [zoom], at: at(89))).isEmpty)
        let events = detector.ingest(MeetingSignals(micInUse: false, runningApps: [zoom], at: at(90)))
        guard case let .meetingEnded(_, reason)? = events.first else {
            Issue.record("expected meetingEnded, got \(events)")
            return
        }
        #expect(reason == .micIdle)
        #expect(detector.activeMeeting == nil)
    }

    @Test("A brief mute does not end the meeting")
    func briefMute() {
        var detector = MeetingDetector()
        _ = detector.ingest(MeetingSignals(micInUse: true, runningApps: [zoom], at: t0))
        _ = detector.ingest(MeetingSignals(micInUse: false, runningApps: [zoom], at: at(50)))
        _ = detector.ingest(MeetingSignals(micInUse: true, runningApps: [zoom], at: at(55)))
        #expect(detector.ingest(MeetingSignals(micInUse: false, runningApps: [zoom], at: at(100))).isEmpty)
        #expect(detector.activeMeeting != nil)
    }

    @Test("Quitting the app ends the meeting at once")
    func appClosed() {
        var detector = MeetingDetector()
        _ = detector.ingest(MeetingSignals(micInUse: true, runningApps: [zoom], at: t0))
        let events = detector.ingest(MeetingSignals(micInUse: true, runningApps: [chrome], at: at(5)))
        guard case let .meetingEnded(context, reason)? = events.first else {
            Issue.record("expected meetingEnded, got \(events)")
            return
        }
        #expect(reason == .appClosed)
        #expect(context.appBundleID == "us.zoom.xos")
    }

    @Test("A calendar-only meeting is not ended by app changes, only by the mic")
    func calendarIgnoresApps() {
        var detector = MeetingDetector()
        let entry = MeetingCalendarEntry(title: "Call", startsAt: at(-60), endsAt: at(1800))
        _ = detector.ingest(MeetingSignals(micInUse: true, calendarNow: entry, at: t0))
        #expect(detector.ingest(MeetingSignals(micInUse: true, runningApps: [], at: at(5))).isEmpty)
        #expect(detector.activeMeeting != nil)
    }

    @Test("The do-not-record list skips a meeting once and never starts it")
    func doNotRecord() {
        var detector = MeetingDetector(doNotRecord: ["FaceTime"])
        let facetime = MeetingSignals.RunningApp(bundleID: "com.apple.FaceTime", name: "FaceTime")
        let first = detector.ingest(MeetingSignals(micInUse: true, runningApps: [facetime], at: t0))
        guard case let .meetingSkipped(_, matched)? = first.first else {
            Issue.record("expected meetingSkipped, got \(first)")
            return
        }
        #expect(matched == "FaceTime")
        #expect(detector.ingest(MeetingSignals(micInUse: true, runningApps: [facetime], at: at(5))).isEmpty)
        #expect(detector.activeMeeting == nil)
        #expect(detector.isSuppressed)
        // After it ends, the detector is ready for the next meeting.
        _ = detector.ingest(MeetingSignals(micInUse: false, runningApps: [facetime], at: at(70)))
        #expect(!detector.isSuppressed)
    }

    @Test("An empty do-not-record list records everything")
    func emptyListRecords() {
        var detector = MeetingDetector(doNotRecord: [])
        #expect(started(detector.ingest(MeetingSignals(micInUse: true, runningApps: [zoom], at: t0))) != nil)
    }

    @Test("Stopping by hand holds the meeting until it really ends")
    func userDismissal() {
        var detector = MeetingDetector()
        _ = detector.ingest(MeetingSignals(micInUse: true, runningApps: [zoom], at: t0))
        #expect(detector.dismissActive(at: at(10)) != nil)
        #expect(detector.ingest(MeetingSignals(micInUse: true, runningApps: [zoom], at: at(20))).isEmpty)
        #expect(detector.activeMeeting == nil)
        // Ends quietly (no meetingEnded — the recorder already stopped).
        #expect(detector.ingest(MeetingSignals(micInUse: false, runningApps: [zoom], at: at(90))).isEmpty)
        // The next call starts again.
        #expect(started(detector.ingest(MeetingSignals(micInUse: true, runningApps: [zoom], at: at(200)))) != nil)
    }
}

@Suite struct MeetingExclusionTests {
    private let context = MeetingContext(
        source: .app,
        appBundleID: "us.zoom.xos",
        appName: "zoom.us",
        title: "Weekly with Sato",
        calendar: MeetingCalendarEntry(
            title: "Weekly with Sato",
            startsAt: Date(timeIntervalSince1970: 0),
            endsAt: Date(timeIntervalSince1970: 3600),
            attendees: ["sato@example.com"]
        ),
        startedAt: Date(timeIntervalSince1970: 0)
    )

    @Test("Matches app, title and attendee domain, case-insensitively")
    func matches() {
        #expect(MeetingExclusion.match(context, against: ["ZOOM.US"]) == "ZOOM.US")
        #expect(MeetingExclusion.match(context, against: ["sato"]) == "sato")
        #expect(MeetingExclusion.match(context, against: ["@example.com"]) == "@example.com")
        #expect(MeetingExclusion.match(context, against: ["us.zoom.xos"]) == "us.zoom.xos")
    }

    @Test("Blank entries and non-matching entries do nothing")
    func noMatch() {
        #expect(MeetingExclusion.match(context, against: ["", "  ", "FaceTime"]) == nil)
    }

    @Test("The rule list splits lines and commas and drops comments")
    func parse() {
        #expect(MeetingRuleList.parse("FaceTime\n# family\n, @example.com ,\n\n") == ["FaceTime", "@example.com"])
        #expect(MeetingRuleList.parse("").isEmpty)
    }

    @Test("Company keywords and attendee domains tag a meeting as company")
    func scope() {
        #expect(MeetingScope.classify(context, keywords: [], domains: []) == .personal)
        #expect(MeetingScope.classify(context, keywords: ["weekly"], domains: []) == .company)
        #expect(MeetingScope.classify(context, keywords: [], domains: ["example.com"]) == .company)
        #expect(MeetingScope.classify(context, keywords: [], domains: ["@example.com"]) == .company)
        #expect(MeetingScope.classify(context, keywords: ["Gugen"], domains: ["gugen.co.jp"]) == .personal)
    }
}
