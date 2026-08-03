import Foundation
import Observation

/// When completion notices for subagents and agent-team members surface.
enum ChildAgentNotificationTiming: String, CaseIterable, PreferenceRepresentable, Sendable {
    case rootResponses
    case allFinished
    case everyCompletion

    var labelKey: String { "settings.behaviour.childAgentTiming.\(rawValue)" }
}

/// How long to wait before nudging the user a second time.
enum AttentionReminderDelay: String, CaseIterable, PreferenceRepresentable, Sendable {
    case off
    case tenMinutes
    case thirtyMinutes
    case oneHour

    var labelKey: String { "settings.behaviour.reminderDelay.\(rawValue)" }

    var interval: TimeInterval? {
        switch self {
        case .off:            nil
        case .tenMinutes:     600
        case .thirtyMinutes:  1800
        case .oneHour:        3600
        }
    }
}

/// How long a session with no clear close signal survives before being dropped.
enum IdleSessionCleanup: String, CaseIterable, PreferenceRepresentable, Sendable {
    case never
    case thirtyMinutes
    case oneHour
    case twoHours
    case fourHours
    case eightHours
    case twentyFourHours

    var labelKey: String { "settings.behaviour.idleCleanup.\(rawValue)" }

    var interval: TimeInterval? {
        switch self {
        case .never:           nil
        case .thirtyMinutes:   1800
        case .oneHour:         3600
        case .twoHours:        7200
        case .fourHours:       14400
        case .eightHours:      28800
        case .twentyFourHours: 86400
        }
    }
}

/// A macOS Focus mode the island can stay quiet during.
enum QuietFocusMode: String, CaseIterable, Sendable {
    case doNotDisturb
    case personal
    case work
    case sleep
    case reduceInterruptions
    case reading
    case gaming
    case driving
    case custom

    var labelKey: String { "settings.behaviour.focusMode.\(rawValue)" }
}

/// Everything about *when* the island opens, closes, makes noise, or stays out of the way.
final class BehaviourSettings: PreferenceGroup {
    let registrar = ObservationRegistrar()
    let store: PreferenceStore

    init(store: PreferenceStore = .standard) {
        self.store = store
    }

    // MARK: Expansion

    var expandOnHover: Bool {
        get { read(\.expandOnHover, Keys.expandOnHover, true) }
        set { write(\.expandOnHover, Keys.expandOnHover, newValue) }
    }

    /// Seconds the pointer must rest on the island before it opens.
    var hoverDuration: Double {
        get { read(\.hoverDuration, Keys.hoverDuration, Defaults.hoverDuration) }
        set { write(\.hoverDuration, Keys.hoverDuration, newValue) }
    }

    var autoExpandOnAgentTeamComplete: Bool {
        get { read(\.autoExpandOnAgentTeamComplete, Keys.autoExpandOnAgentTeamComplete, false) }
        set { write(\.autoExpandOnAgentTeamComplete, Keys.autoExpandOnAgentTeamComplete, newValue) }
    }

    // MARK: Visibility

    var hideInFullscreen: Bool {
        get { read(\.hideInFullscreen, Keys.hideInFullscreen, false) }
        set { write(\.hideInFullscreen, Keys.hideInFullscreen, newValue) }
    }

    /// Skip auto-expanding while the agent's own terminal tab is already in front.
    var smartSuppression: Bool {
        get { read(\.smartSuppression, Keys.smartSuppression, true) }
        set { write(\.smartSuppression, Keys.smartSuppression, newValue) }
    }

    var autoHideWhenIdle: Bool {
        get { read(\.autoHideWhenIdle, Keys.autoHideWhenIdle, false) }
        set { write(\.autoHideWhenIdle, Keys.autoHideWhenIdle, newValue) }
    }

    // MARK: Dismissal

    var autoCollapseOnLeave: Bool {
        get { read(\.autoCollapseOnLeave, Keys.autoCollapseOnLeave, true) }
        set { write(\.autoCollapseOnLeave, Keys.autoCollapseOnLeave, newValue) }
    }

    /// Seconds an auto-revealed panel stays open before folding back on its own.
    var autoRevealDwell: Double {
        get { read(\.autoRevealDwell, Keys.autoRevealDwell, Defaults.autoRevealDwell) }
        set { write(\.autoRevealDwell, Keys.autoRevealDwell, newValue) }
    }

    var dismissOnOutsideClick: Bool {
        get { read(\.dismissOnOutsideClick, Keys.dismissOnOutsideClick, true) }
        set { write(\.dismissOnOutsideClick, Keys.dismissOnOutsideClick, newValue) }
    }

    // MARK: Interaction

    var disableClickToJump: Bool {
        get { read(\.disableClickToJump, Keys.disableClickToJump, false) }
        set { write(\.disableClickToJump, Keys.disableClickToJump, newValue) }
    }

    // MARK: Completion notices

    var expandOnCompletion: Bool {
        get { read(\.expandOnCompletion, Keys.expandOnCompletion, true) }
        set { write(\.expandOnCompletion, Keys.expandOnCompletion, newValue) }
    }

    var childAgentNotificationTiming: ChildAgentNotificationTiming {
        get { read(\.childAgentNotificationTiming, Keys.childAgentNotificationTiming, .allFinished) }
        set { write(\.childAgentNotificationTiming, Keys.childAgentNotificationTiming, newValue) }
    }

    // MARK: Follow-up reminders

    var reminderDelay: AttentionReminderDelay {
        get { read(\.reminderDelay, Keys.reminderDelay, .off) }
        set { write(\.reminderDelay, Keys.reminderDelay, newValue) }
    }

    var remindNeedsResponse: Bool {
        get { read(\.remindNeedsResponse, Keys.remindNeedsResponse, true) }
        set { write(\.remindNeedsResponse, Keys.remindNeedsResponse, newValue) }
    }

    var remindCompletedWork: Bool {
        get { read(\.remindCompletedWork, Keys.remindCompletedWork, false) }
        set { write(\.remindCompletedWork, Keys.remindCompletedWork, newValue) }
    }

    // MARK: Quiet scenes

    /// Raw values of the `QuietFocusMode` cases the island should stay quiet during.
    var quietFocusModes: [String] {
        get { read(\.quietFocusModes, Keys.quietFocusModes, []) }
        set { write(\.quietFocusModes, Keys.quietFocusModes, newValue) }
    }

    func isQuiet(during mode: QuietFocusMode) -> Bool {
        quietFocusModes.contains(mode.rawValue)
    }

    func setQuiet(_ quiet: Bool, during mode: QuietFocusMode) {
        var modes = Set(quietFocusModes)
        if quiet { modes.insert(mode.rawValue) } else { modes.remove(mode.rawValue) }
        quietFocusModes = QuietFocusMode.allCases
            .map(\.rawValue)
            .filter(modes.contains)
    }

    var quietWhenScreenObscured: Bool {
        get { read(\.quietWhenScreenObscured, Keys.quietWhenScreenObscured, true) }
        set { write(\.quietWhenScreenObscured, Keys.quietWhenScreenObscured, newValue) }
    }

    var quietWhenScreenCaptured: Bool {
        get { read(\.quietWhenScreenCaptured, Keys.quietWhenScreenCaptured, true) }
        set { write(\.quietWhenScreenCaptured, Keys.quietWhenScreenCaptured, newValue) }
    }

    // MARK: Idle cleanup

    var idleSessionCleanup: IdleSessionCleanup {
        get { read(\.idleSessionCleanup, Keys.idleSessionCleanup, .twoHours) }
        set { write(\.idleSessionCleanup, Keys.idleSessionCleanup, newValue) }
    }
}

extension BehaviourSettings {
    enum Defaults {
        static let hoverDuration: Double = 0.15
        static let hoverDurationRange: ClosedRange<Double> = 0...1.0
        /// Kept at the value the app already shipped so nobody's panel starts
        /// closing sooner than it used to just because the setting now exists.
        /// The reference product offers this as a picker, so do the same.
        static let autoRevealDwell: Double = 10
        static let autoRevealDwellOptions: [Double] = [3, 5, 10, 15, 30]
    }

    enum Keys {
        static let expandOnHover = "behaviour.expandOnHover"
        static let hoverDuration = "behaviour.hoverDuration"
        static let autoExpandOnAgentTeamComplete = "behaviour.autoExpandOnAgentTeamComplete"
        static let hideInFullscreen = "behaviour.hideInFullscreen"
        static let smartSuppression = "behaviour.smartSuppression"
        static let autoHideWhenIdle = "behaviour.autoHideWhenIdle"
        static let autoCollapseOnLeave = "behaviour.autoCollapseOnLeave"
        static let autoRevealDwell = "behaviour.autoRevealDwell"
        static let dismissOnOutsideClick = "behaviour.dismissOnOutsideClick"
        static let disableClickToJump = "behaviour.disableClickToJump"
        static let expandOnCompletion = "behaviour.expandOnCompletion"
        static let childAgentNotificationTiming = "behaviour.childAgentNotificationTiming"
        static let reminderDelay = "behaviour.reminder.delay"
        static let remindNeedsResponse = "behaviour.reminder.needsResponse"
        static let remindCompletedWork = "behaviour.reminder.completedWork"
        static let quietFocusModes = "behaviour.quiet.focusModes"
        static let quietWhenScreenObscured = "behaviour.quiet.screenObscured"
        static let quietWhenScreenCaptured = "behaviour.quiet.screenCaptured"
        static let idleSessionCleanup = "behaviour.idleSessionCleanup"
    }
}
