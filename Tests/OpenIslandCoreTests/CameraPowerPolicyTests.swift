import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Camera power policy")
struct CameraPowerPolicyTests {
    private func conditions(
        isOnAC: Bool = true,
        batteryPercent: Int? = 100,
        isLowPowerMode: Bool = false,
        thermalState: ProcessInfo.ThermalState = .nominal,
        isLidClosed: Bool = false
    ) -> CameraPowerPolicy.Conditions {
        .init(
            isOnAC: isOnAC,
            batteryPercent: batteryPercent,
            isLowPowerMode: isLowPowerMode,
            thermalState: thermalState,
            isLidClosed: isLidClosed
        )
    }

    @Test("An ordinary machine may hold the camera open")
    func allowsWhenNothingIsWrong() {
        #expect(CameraPowerPolicy.allowsSustainedCamera(conditions()))
        #expect(CameraPowerPolicy.refusal(for: conditions()) == nil)
    }

    /// Not a trade-off: the built-in camera is facing the keyboard.
    @Test("A closed lid refuses before anything else")
    func lidClosedWinsOverEverything() {
        let everythingWrong = conditions(
            isOnAC: false,
            batteryPercent: 5,
            isLowPowerMode: true,
            thermalState: .critical,
            isLidClosed: true
        )
        #expect(CameraPowerPolicy.refusal(for: everythingWrong) == .lidClosed)
    }

    @Test("A hot Mac is not given more work, even on mains")
    func thermalCutoutIgnoresPower() {
        #expect(CameraPowerPolicy.refusal(for: conditions(thermalState: .serious)) == .tooHot)
        #expect(CameraPowerPolicy.refusal(for: conditions(thermalState: .critical)) == .tooHot)
        // Fair is fair — a warm machine is still fine.
        #expect(CameraPowerPolicy.refusal(for: conditions(thermalState: .fair)) == nil)
    }

    @Test("A low battery refuses only when unplugged")
    func batteryFloorAppliesOnBatteryOnly() {
        #expect(CameraPowerPolicy.refusal(for: conditions(isOnAC: false, batteryPercent: 15)) == .batteryLow)
        #expect(CameraPowerPolicy.refusal(for: conditions(isOnAC: true, batteryPercent: 15)) == nil)
    }

    @Test("The floor itself refuses")
    func floorIsInclusive() {
        let atFloor = conditions(isOnAC: false, batteryPercent: CameraPowerPolicy.batteryFloor)
        #expect(CameraPowerPolicy.refusal(for: atFloor) == .batteryLow)
        let justAbove = conditions(isOnAC: false, batteryPercent: CameraPowerPolicy.batteryFloor + 1)
        #expect(CameraPowerPolicy.refusal(for: justAbove) == nil)
    }

    /// The user asked the machine to do less, and this is exactly what they meant.
    @Test("Low power mode refuses on battery and is ignored on mains")
    func lowPowerModeAppliesOnBatteryOnly() {
        #expect(CameraPowerPolicy.refusal(for: conditions(isOnAC: false, isLowPowerMode: true)) == .lowPowerMode)
        #expect(CameraPowerPolicy.refusal(for: conditions(isOnAC: true, isLowPowerMode: true)) == nil)
    }

    /// A desktop has no battery to protect.
    @Test("A machine with no battery is never refused for power")
    func desktopIsNeverRefusedForPower() {
        let desktop = conditions(isOnAC: true, batteryPercent: nil)
        #expect(CameraPowerPolicy.allowsSustainedCamera(desktop))
    }

    @Test("Every refusal carries its own sentence")
    func refusalsHaveDistinctKeys() {
        let all: [CameraPowerPolicy.Refusal] = [.lidClosed, .tooHot, .batteryLow, .lowPowerMode]
        #expect(Set(all.map(\.noticeKey)).count == all.count)
    }
}
