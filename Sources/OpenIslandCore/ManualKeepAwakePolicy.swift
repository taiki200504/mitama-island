import Foundation

public enum ManualKeepAwakePolicy {
    public enum Mode: String, CaseIterable, Sendable {
        case alwaysOn, off, oneHour, threeHours, eightHours, indefinite, untilFinished

        public var duration: TimeInterval? {
            switch self {
            case .oneHour: 3600
            case .threeHours: 10800
            case .eightHours: 28800
            default: nil
            }
        }

        public var labelKey: String { "keepAwake.mode.\(rawValue)" }
    }

    public enum Reason: String, Equatable, Sendable {
        case disabled, expired, tooHot, batteryLow, lidClosedOnBattery, nothingRunning
        public var isSafetyRelease: Bool {
            self == .tooHot || self == .batteryLow || self == .lidClosedOnBattery
        }
    }

    public enum Decision: Equatable, Sendable {
        case hold(displayToo: Bool)
        case release(Reason)
    }

    public static func decide(
        mode: Mode, now: Date, startedAt: Date,
        conditions: CameraPowerPolicy.Conditions, runningCount: Int,
        displayToo: Bool = false, wasSuspended: Bool = false
    ) -> Decision {
        guard mode != .off else { return .release(.disabled) }
        if conditions.thermalState == .serious || conditions.thermalState == .critical {
            return .release(.tooHot)
        }
        if mode == .alwaysOn {
            let batteryFloor = wasSuspended ? 30 : 25
            if !conditions.isOnAC, let battery = conditions.batteryPercent, battery < batteryFloor {
                return .release(.batteryLow)
            }
            return .hold(displayToo: displayToo)
        }
        if !conditions.isOnAC {
            if let battery = conditions.batteryPercent, battery < 20 { return .release(.batteryLow) }
            if conditions.isLidClosed { return .release(.lidClosedOnBattery) }
        }
        if let duration = mode.duration, now >= startedAt.addingTimeInterval(duration) {
            return .release(.expired)
        }
        if mode == .untilFinished && runningCount == 0 { return .release(.nothingRunning) }
        return .hold(displayToo: displayToo)
    }
}
