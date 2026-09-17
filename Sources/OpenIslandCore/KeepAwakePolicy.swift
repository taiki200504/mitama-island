import Foundation

/// Whether to keep the Mac from idling to sleep right now.
///
/// The point is narrow: an agent is mid-task and the person has walked away,
/// so the machine should not doze off and suspend the work. Everything else is
/// a reason to let it sleep — including a laptop on battery, where staying
/// awake in a bag is how a Mac cooks itself.
public enum KeepAwakePolicy: Sendable {
    public enum Decision: Equatable, Sendable {
        case hold
        case release(Reason)
    }

    public enum Reason: String, Equatable, Sendable {
        case disabled
        case nothingRunning
        case lidClosed
        case tooHot
        case onBattery
        case lowPowerMode
    }

    public static func decide(
        enabled: Bool,
        runningCount: Int,
        conditions: CameraPowerPolicy.Conditions
    ) -> Decision {
        guard enabled else { return .release(.disabled) }
        guard runningCount > 0 else { return .release(.nothingRunning) }
        if conditions.isLidClosed { return .release(.lidClosed) }
        if conditions.thermalState == .serious || conditions.thermalState == .critical {
            return .release(.tooHot)
        }
        // Mains power only. Unlike the camera there is no "battery above 20%"
        // allowance: this hold lasts as long as an agent runs, which can be hours.
        guard conditions.isOnAC else { return .release(.onBattery) }
        if conditions.isLowPowerMode { return .release(.lowPowerMode) }
        return .hold
    }
}
