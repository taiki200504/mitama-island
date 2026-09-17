import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Keep awake policy")
struct KeepAwakePolicyTests {
    private func conditions(
        ac: Bool = true,
        battery: Int? = 80,
        lowPower: Bool = false,
        thermal: ProcessInfo.ThermalState = .nominal,
        lid: Bool = false
    ) -> CameraPowerPolicy.Conditions {
        .init(isOnAC: ac, batteryPercent: battery, isLowPowerMode: lowPower, thermalState: thermal, isLidClosed: lid)
    }

    @Test("Holds only when enabled, something runs, and the machine is plugged in and cool")
    func holds() {
        #expect(KeepAwakePolicy.decide(enabled: true, runningCount: 1, conditions: conditions()) == .hold)
    }

    @Test("Every other case lets the Mac sleep, with the reason")
    func releases() {
        #expect(KeepAwakePolicy.decide(enabled: false, runningCount: 3, conditions: conditions()) == .release(.disabled))
        #expect(KeepAwakePolicy.decide(enabled: true, runningCount: 0, conditions: conditions()) == .release(.nothingRunning))
        #expect(KeepAwakePolicy.decide(enabled: true, runningCount: 1, conditions: conditions(lid: true)) == .release(.lidClosed))
        #expect(KeepAwakePolicy.decide(enabled: true, runningCount: 1, conditions: conditions(thermal: .serious)) == .release(.tooHot))
        #expect(KeepAwakePolicy.decide(enabled: true, runningCount: 1, conditions: conditions(ac: false, battery: 95)) == .release(.onBattery))
        #expect(KeepAwakePolicy.decide(enabled: true, runningCount: 1, conditions: conditions(lowPower: true)) == .release(.lowPowerMode))
    }
}
