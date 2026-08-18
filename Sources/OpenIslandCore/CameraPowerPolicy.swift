import Foundation

/// Whether the machine is in a state where holding the camera open is fair.
///
/// The sustained camera — open for as long as a card is waiting — is the one
/// path in this app that runs a capture session for minutes rather than
/// seconds. On a laptop that is a real cost, and there are moments where it is
/// simply wrong: a shut lid has no view, and a hot Mac should not be given more
/// work.
///
/// Pure so the rules can be read and tested without a battery.
public enum CameraPowerPolicy: Sendable {
    public struct Conditions: Equatable, Sendable {
        public var isOnAC: Bool
        /// Nil on a desktop, where battery rules do not apply at all.
        public var batteryPercent: Int?
        public var isLowPowerMode: Bool
        public var thermalState: ProcessInfo.ThermalState
        public var isLidClosed: Bool

        public init(
            isOnAC: Bool,
            batteryPercent: Int?,
            isLowPowerMode: Bool,
            thermalState: ProcessInfo.ThermalState,
            isLidClosed: Bool
        ) {
            self.isOnAC = isOnAC
            self.batteryPercent = batteryPercent
            self.isLowPowerMode = isLowPowerMode
            self.thermalState = thermalState
            self.isLidClosed = isLidClosed
        }
    }

    /// Why the camera is being kept shut, for the sentence shown on the island.
    public enum Refusal: String, Equatable, Sendable {
        case lidClosed
        case tooHot
        case batteryLow
        case lowPowerMode

        public var noticeKey: String { "camera.power.\(rawValue)" }
    }

    /// Below this, on battery, the camera stays shut.
    public static let batteryFloor = 20

    public static func refusal(for conditions: Conditions) -> Refusal? {
        // A closed lid is first because it is not a trade-off: the built-in
        // camera is facing the keyboard.
        if conditions.isLidClosed { return .lidClosed }

        if conditions.thermalState == .serious || conditions.thermalState == .critical {
            return .tooHot
        }

        // Everything below is about spending the battery, so mains power ends
        // the question.
        guard !conditions.isOnAC else { return nil }

        if let percent = conditions.batteryPercent, percent <= batteryFloor { return .batteryLow }
        // The user asked the machine to do less. A camera watching for a hand
        // that may never come is exactly what they meant.
        if conditions.isLowPowerMode { return .lowPowerMode }

        return nil
    }

    public static func allowsSustainedCamera(_ conditions: Conditions) -> Bool {
        refusal(for: conditions) == nil
    }
}
