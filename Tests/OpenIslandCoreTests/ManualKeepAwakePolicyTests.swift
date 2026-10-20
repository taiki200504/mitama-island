import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Manual keep awake policy")
struct ManualKeepAwakePolicyTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    private func decide(
        _ mode: ManualKeepAwakePolicy.Mode = .indefinite,
        elapsed: TimeInterval = 0, ac: Bool = true, battery: Int? = 80,
        thermal: ProcessInfo.ThermalState = .nominal, lid: Bool = false,
        running: Int = 1, display: Bool = false, suspended: Bool = false
    ) -> ManualKeepAwakePolicy.Decision {
        ManualKeepAwakePolicy.decide(
            mode: mode, now: start.addingTimeInterval(elapsed), startedAt: start,
            conditions: .init(isOnAC: ac, batteryPercent: battery, isLowPowerMode: true,
                              thermalState: thermal, isLidClosed: lid),
            runningCount: running, displayToo: display, wasSuspended: suspended
        )
    }

    @Test func off() { #expect(decide(.off) == .release(.disabled)) }

    @Test func expiry() {
        for mode in [ManualKeepAwakePolicy.Mode.oneHour, .threeHours, .eightHours] {
            let duration = mode.duration!
            #expect(decide(mode, elapsed: duration - 1) == .hold(displayToo: false))
            #expect(decide(mode, elapsed: duration) == .release(.expired))
            #expect(decide(mode, elapsed: duration + 1) == .release(.expired))
        }
    }

    @Test func heat() {
        #expect(decide(thermal: .serious) == .release(.tooHot))
        #expect(decide(thermal: .critical) == .release(.tooHot))
        #expect(decide(thermal: .fair) == .hold(displayToo: false))
    }

    @Test func batteryFloor() {
        #expect(decide(ac: false, battery: 19) == .release(.batteryLow))
        #expect(decide(ac: false, battery: 20) == .hold(displayToo: false))
        #expect(decide(ac: true, battery: 1) == .hold(displayToo: false))
    }

    @Test func closedLidOnBattery() {
        #expect(decide(ac: false, lid: true) == .release(.lidClosedOnBattery))
        #expect(decide(lid: true) == .hold(displayToo: false))
    }

    @Test func untilFinished() {
        #expect(decide(.untilFinished, running: 0) == .release(.nothingRunning))
        #expect(decide(.untilFinished, running: 2) == .hold(displayToo: false))
    }

    @Test func indefiniteSurvivesRestartAndIdle() {
        #expect(decide(elapsed: 1_000_000, running: 0) == .hold(displayToo: false))
    }

    @Test func display() { #expect(decide(display: true) == .hold(displayToo: true)) }

    @Test func desktop() { #expect(decide(battery: nil) == .hold(displayToo: false)) }

    @Test func safetyReasons() {
        #expect(ManualKeepAwakePolicy.Reason.tooHot.isSafetyRelease)
        #expect(ManualKeepAwakePolicy.Reason.batteryLow.isSafetyRelease)
        #expect(ManualKeepAwakePolicy.Reason.lidClosedOnBattery.isSafetyRelease)
        #expect(!ManualKeepAwakePolicy.Reason.expired.isSafetyRelease)
    }
    @Test func alwaysOnClosedLid() {
        #expect(decide(.alwaysOn, lid: true) == .hold(displayToo: false))
        #expect(decide(.alwaysOn, ac: false, battery: 50, lid: true) == .hold(displayToo: false))
    }

    @Test func alwaysOnBatteryHysteresis() {
        #expect(decide(.alwaysOn, ac: false, battery: 24) == .release(.batteryLow))
        #expect(decide(.alwaysOn, ac: false, battery: 25) == .hold(displayToo: false))
        #expect(decide(.alwaysOn, ac: false, battery: 27, suspended: true) == .release(.batteryLow))
        #expect(decide(.alwaysOn, ac: false, battery: 30, suspended: true) == .hold(displayToo: false))
        #expect(decide(.alwaysOn, ac: false, battery: 31, suspended: true) == .hold(displayToo: false))
        #expect(decide(.alwaysOn, battery: 24, suspended: true) == .hold(displayToo: false))
    }

    @Test func alwaysOnThermalRecovery() {
        for thermal in [ProcessInfo.ThermalState.serious, .critical] {
            #expect(decide(.alwaysOn, thermal: thermal) == .release(.tooHot))
        }
        for thermal in [ProcessInfo.ThermalState.nominal, .fair] {
            #expect(decide(.alwaysOn, thermal: thermal, suspended: true) == .hold(displayToo: false))
        }
    }

    @Test func alwaysOnPersistsAndResumes() {
        let mode = ManualKeepAwakePolicy.Mode(rawValue: "alwaysOn")!
        #expect(decide(mode, ac: false, battery: 24) == .release(.batteryLow))
        #expect(mode == .alwaysOn)
        #expect(decide(mode, elapsed: 1_000_000, running: 0, display: true, suspended: true)
                == .hold(displayToo: true))
        #expect(mode.duration == nil)
        #expect(ManualKeepAwakePolicy.Mode.allCases.first == .alwaysOn)
    }

}
