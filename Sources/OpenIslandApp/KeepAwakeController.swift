import Foundation
import IOKit.pwr_mgt
import OpenIslandCore

/// Owns separate system and optional display assertions; both die with the process.
@MainActor
final class KeepAwakeController {
    private var systemID: IOPMAssertionID = 0
    private var displayID: IOPMAssertionID = 0
    private(set) var isHolding = false

    func apply(_ decision: KeepAwakePolicy.Decision, displayToo: Bool = false) {
        let hold = decision == .hold
        update(&systemID, type: kIOPMAssertionTypePreventUserIdleSystemSleep, hold: hold)
        update(&displayID, type: kIOPMAssertionTypePreventUserIdleDisplaySleep, hold: hold && displayToo)
        isHolding = systemID != 0
    }

    private func update(_ id: inout IOPMAssertionID, type: String, hold: Bool) {
        if hold && id == 0 {
            var created: IOPMAssertionID = 0
            if IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                          "Mitama Island: stay awake" as CFString, &created) == kIOReturnSuccess {
                id = created
            }
        } else if !hold && id != 0 {
            IOPMAssertionRelease(id)
            id = 0
        }
    }
}
