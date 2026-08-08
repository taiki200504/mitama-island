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

    var labelKey: String { "settings.sound.event.\(rawValue)" }

    var preferenceKey: String { "sound.event.\(rawValue)" }

    /// Kept so the settings pane and its tests keep one shared answer to
    /// "would this ever be heard". Everything left is raised.
    var isRaised: Bool { true }

    static var raisedEvents: [NotificationSoundEvent] { allCases }
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

    /// Whether a sound should be heard for this event right now.
    func shouldPlay(_ event: NotificationSoundEvent, at date: Date, calendar: Calendar = .current) -> Bool {
        guard !isMuted, event.isRaised else { return false }
        return !isWithinQuietHours(date, calendar: calendar)
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
        /// Mirrors `NotificationSoundService.defaultSoundName`, which is main-actor
        /// isolated and so cannot be referenced from here.
        static let soundName = "Bottle"
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
    }
}
