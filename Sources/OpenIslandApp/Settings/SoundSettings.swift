import Foundation
import Observation

/// A moment the island can make a sound at.
///
/// Every case here is raised somewhere in the app. Three that the settings
/// surface used to list — an error chime, an idle reminder and a "quota
/// refreshed" chime — were removed rather than left as rows that could never be
/// heard: the app has no error state, no idle nag, and nobody asked to be
/// congratulated on a reset quota.
enum NotificationSoundEvent: String, CaseIterable, Sendable {
    case approvalNeeded
    case answerNeeded
    case taskComplete
    case sessionStart
    /// The agent is compacting its conversation — the moment work slows down.
    case contextLimit
    case usageAlmostFull
    case islandOpenedByGesture
    case islandOpened
    case islandClosed
    case selection
    case confirm
    case approve
    case reject
    /// Available for assignment, like `timerFinished` and `eventStarting`
    /// below — nothing in this app raises it yet.
    case warning
    /// Not raised in this PR; reserved for a countdown feature.
    case timerFinished
    /// Not raised in this PR; reserved for a calendar feature.
    case eventStarting
    /// Not raised in this PR; reserved for a lock-screen feature.
    case lockScan
    /// Not raised in this PR; reserved for a lock-screen feature.
    case unlock

    var labelKey: String { "settings.sound.event.\(rawValue)" }

    var preferenceKey: String { "sound.event.\(rawValue)" }

    /// Kept so the settings pane and its tests keep one shared answer to
    /// "would this ever be heard". Everything left is raised.
    var isRaised: Bool { true }

    /// Chrome the island itself makes while being operated — open, close,
    /// moving the selection, confirming, approving, rejecting. These share one
    /// "Interface sounds" toggle rather than a settings row each: nobody wants
    /// to individually configure the sound a switcher row makes when the
    /// pointer moves over it.
    var isUIFeedback: Bool {
        switch self {
        case .islandOpened, .islandClosed, .selection, .confirm, .approve, .reject:
            true
        default:
            false
        }
    }

    /// Whether this gets its own row in the sound settings pane. UI feedback
    /// (see `isUIFeedback`) is deliberately excluded from that list.
    var isUserAssignable: Bool { !isUIFeedback }

    static var raisedEvents: [NotificationSoundEvent] { allCases }

    static var assignableEvents: [NotificationSoundEvent] { allCases.filter(\.isUserAssignable) }
}

/// Whether sound plays, how loud, which sound per event, and when to stay quiet.
final class SoundSettings: PreferenceGroup {
    let registrar = ObservationRegistrar()
    let store: PreferenceStore

    init(store: PreferenceStore = .standard) {
        self.store = store
    }

    /// Shares its key with the island's own speaker button, so muting from
    /// either place shows up in the other.
    var isMuted: Bool {
        get { read(\.isMuted, Keys.muted, false) }
        set { write(\.isMuted, Keys.muted, newValue) }
    }

    /// Zero to one, applied to the played sound.
    var volume: Double {
        get { read(\.volume, Keys.volume, Defaults.volume) }
        set { write(\.volume, Keys.volume, min(max(newValue, 0), 1)) }
    }

    /// Whether the island's own chrome — open, close, select, confirm,
    /// approve, reject — makes noise. On by default, matching how the app
    /// always sounded before this became separable from notification sounds.
    var uiSoundsEnabled: Bool {
        get { read(\.uiSoundsEnabled, Keys.uiSoundsEnabled, true) }
        set { write(\.uiSoundsEnabled, Keys.uiSoundsEnabled, newValue) }
    }

    // MARK: Quiet hours

    var quietHoursEnabled: Bool {
        get { read(\.quietHoursEnabled, Keys.quietHoursEnabled, false) }
        set { write(\.quietHoursEnabled, Keys.quietHoursEnabled, newValue) }
    }

    /// Minutes past midnight.
    var quietHoursStart: Int {
        get { read(\.quietHoursStart, Keys.quietHoursStart, Defaults.quietHoursStart) }
        set { write(\.quietHoursStart, Keys.quietHoursStart, Self.clampToDay(newValue)) }
    }

    var quietHoursEnd: Int {
        get { read(\.quietHoursEnd, Keys.quietHoursEnd, Defaults.quietHoursEnd) }
        set { write(\.quietHoursEnd, Keys.quietHoursEnd, Self.clampToDay(newValue)) }
    }

    // MARK: Per-event assignment

    /// The theme picks the default, and a choice the user made outranks it.
    ///
    /// Reading the theme here rather than rewriting stored values on every theme
    /// switch: overwriting them would silently discard sounds someone had picked
    /// for themselves, and switching back would not bring them back.
    @MainActor
    func soundName(for event: NotificationSoundEvent) -> String {
        registrar.access(self, keyPath: \.assignmentsRevision)
        return store.value(
            event.preferenceKey,
            default: IslandThemes.current.soundProfile.soundName(for: event)
        )
    }

    func setSoundName(_ name: String, for event: NotificationSoundEvent) {
        registrar.withMutation(of: self, keyPath: \.assignmentsRevision) {
            store.setValue(name, forKey: event.preferenceKey)
        }
    }

    /// Observation anchor for the assignment set. Never read for its value.
    var assignmentsRevision: Int {
        store.value(Keys.revision, default: 0)
    }

    // MARK: Decisions

    /// Whether anything should be heard right now, independent of which
    /// event is asking — mute and quiet hours apply the same way to every
    /// sound, including the login sequence's cues, which carry no
    /// `NotificationSoundEvent` of their own to gate through `shouldPlay`.
    func shouldPlayAnything(at date: Date, calendar: Calendar = .current) -> Bool {
        !isMuted && !isWithinQuietHours(date, calendar: calendar)
    }

    /// Whether a sound should be heard for this event right now.
    func shouldPlay(_ event: NotificationSoundEvent, at date: Date, calendar: Calendar = .current) -> Bool {
        guard event.isRaised else { return false }
        guard !event.isUIFeedback || uiSoundsEnabled else { return false }
        return shouldPlayAnything(at: date, calendar: calendar)
    }

    /// Handles ranges that wrap past midnight, which is the common case for a
    /// "stay quiet overnight" setting.
    func isWithinQuietHours(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard quietHoursEnabled, quietHoursStart != quietHoursEnd else { return false }

        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)

        if quietHoursStart < quietHoursEnd {
            return minute >= quietHoursStart && minute < quietHoursEnd
        }
        return minute >= quietHoursStart || minute < quietHoursEnd
    }

    private static func clampToDay(_ minutes: Int) -> Int {
        min(max(minutes, 0), 24 * 60 - 1)
    }
}

extension SoundSettings {
    enum Defaults {
        /// Full volume, matching how the app played before this became adjustable.
        static let volume: Double = 1.0
        /// 22:00 to 08:00.
        static let quietHoursStart = 22 * 60
        static let quietHoursEnd = 8 * 60
    }

    enum Keys {
        /// Deliberately the key the island's speaker button already writes.
        static let muted = "overlay.sound.muted"
        static let volume = "sound.volume"
        static let quietHoursEnabled = "sound.quietHours.enabled"
        static let quietHoursStart = "sound.quietHours.start"
        static let quietHoursEnd = "sound.quietHours.end"
        static let revision = "sound.assignmentsRevision"
        static let uiSoundsEnabled = "sound.ui.enabled"
    }
}
