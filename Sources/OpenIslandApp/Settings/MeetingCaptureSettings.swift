import Foundation
import Observation

/// Meeting auto-capture (mitama v3 §24, F2).
///
/// On by default: the owner decided every personal meeting is recorded
/// automatically. It is a different bargain from earshot, which stays paused
/// during calls — this records only while a meeting is detected, into its own
/// folder, and shows a red mark on the island for as long as it runs.
///
/// The lists are plain text, one entry per line, so they can be edited without
/// a dedicated list editor (`MeetingRuleList.parse`).
final class MeetingCaptureSettings: PreferenceGroup {
    let registrar = ObservationRegistrar()
    let store: PreferenceStore

    init(store: PreferenceStore = .standard) {
        self.store = store
    }

    var isEnabled: Bool {
        get { read(\.isEnabled, Keys.enabled, true) }
        set { write(\.isEnabled, Keys.enabled, newValue) }
    }

    /// Apps, titles, people or `@domain`s never to record. Starts empty.
    var doNotRecordText: String {
        get { read(\.doNotRecordText, Keys.doNotRecord, "") }
        set { write(\.doNotRecordText, Keys.doNotRecord, newValue) }
    }

    /// Words in a meeting title or calendar name that make it a company
    /// meeting. Company meetings are still recorded; the manifest says
    /// `scope: company` and mitama-os routes the notes elsewhere.
    var companyKeywordsText: String {
        get { read(\.companyKeywordsText, Keys.companyKeywords, Defaults.companyKeywords) }
        set { write(\.companyKeywordsText, Keys.companyKeywords, newValue) }
    }

    /// Attendee e-mail domains that make it a company meeting.
    var companyDomainsText: String {
        get { read(\.companyDomainsText, Keys.companyDomains, "") }
        set { write(\.companyDomainsText, Keys.companyDomains, newValue) }
    }

    /// Where finished meetings are handed to mitama-os. `~` is expanded.
    var inboxPath: String {
        get { read(\.inboxPath, Keys.inboxPath, Defaults.inboxPath) }
        set { write(\.inboxPath, Keys.inboxPath, newValue) }
    }
}

extension MeetingCaptureSettings {
    enum Defaults {
        static let companyKeywords = "Gugen\nマカセタ"
        static let inboxPath = "~/.mitama/meetings/inbox"
    }

    enum Keys {
        static let enabled = "meetingCapture.enabled"
        static let doNotRecord = "meetingCapture.doNotRecord"
        static let companyKeywords = "meetingCapture.companyKeywords"
        static let companyDomains = "meetingCapture.companyDomains"
        static let inboxPath = "meetingCapture.inboxPath"
    }
}
