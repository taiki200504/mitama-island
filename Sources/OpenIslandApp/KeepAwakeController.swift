import Foundation
import IOKit.pwr_mgt
import OpenIslandCore

/// Owns the one power assertion that keeps the system from idle sleep while
/// agents work. The display is still allowed to sleep — the point is the
/// work, not the screen. Lives as long as the app; the kernel drops the
/// assertion with the process, so there is no teardown path to get wrong.
@MainActor
final class KeepAwakeController {
    private var assertionID: IOPMAssertionID = 0
    private(set) var isHolding = false

    func apply(_ decision: KeepAwakePolicy.Decision) {
        switch decision {
        case .hold:
            guard !isHolding else { return }
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Mitama Island: an agent is still working" as CFString,
                &id
            )
            guard result == kIOReturnSuccess else { return }
            assertionID = id
            isHolding = true
        case .release:
            guard isHolding else { return }
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            isHolding = false
        }
    }
}
