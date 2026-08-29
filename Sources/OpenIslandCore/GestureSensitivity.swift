import Foundation

/// How hard a hand has to try before the camera counts it.
///
/// One knob rather than four. The thresholds underneath — how long a pose is
/// held, how long before it may fire again — are the kind of number that only
/// means something once you have watched it fail, and nobody can pick them
/// from a settings pane. Three named points do carry meaning: the same gesture
/// went off when it was not meant to, or it did not go off when it was.
public enum GestureSensitivity: String, CaseIterable, Equatable, Sendable {
    /// Deliberate holds only. For a camera that fires when it should not.
    case low
    /// What the detectors shipped with.
    case medium
    /// Quicker to believe you. For a camera that never fires.
    case high

    public static let `default` = GestureSensitivity.medium

    /// Key into `Localizable.strings`.
    public var labelKey: String { "settings.camera.sensitivity.\(rawValue)" }

    /// Unknown values — a downgrade, a hand-edited plist — read as the middle
    /// setting rather than as a failure to decode.
    public init(rawValue: String) {
        switch rawValue {
        case "low": self = .low
        case "high": self = .high
        default: self = .medium
        }
    }

    /// The hold that turns a raised palm into an answer.
    ///
    /// A longer hold is the honest way to be less sensitive: it costs the user
    /// time rather than accuracy, whereas a stricter pose test just moves the
    /// failure to a hand that is held slightly wrong. The cooldown moves with
    /// it, because a hand is usually still up when the gesture fires and a
    /// short cooldown fires again off the same hold.
    public var palmHold: PoseHoldDetector.Configuration {
        switch self {
        case .low:    .init(minimumHoldDuration: 1.1, cooldownDuration: 3.0)
        case .medium: .init(minimumHoldDuration: 0.6, cooldownDuration: 2.0)
        case .high:   .init(minimumHoldDuration: 0.35, cooldownDuration: 1.2)
        }
    }
}
