import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Session vitals")
struct SessionVitalsTests {
    @Test("Full and calm for the first minute, then draining")
    func drains() {
        #expect(SessionVitals.hp(waitingFor: 0) == (1, .fresh))
        #expect(SessionVitals.hp(waitingFor: 59) == (1, .fresh))
        #expect(SessionVitals.hp(waitingFor: 300).fraction < 1)
        #expect(SessionVitals.hp(waitingFor: 300).band == .fresh)
        #expect(SessionVitals.hp(waitingFor: 600).band == .overdue)
        #expect(SessionVitals.hp(waitingFor: 3600).band == .critical)
    }

    @Test("Never reaches empty, and never rises as time passes")
    func neverEmptyAndMonotonic() {
        var previous = 1.0
        for seconds in stride(from: 0.0, through: 7200, by: 30) {
            let hp = SessionVitals.hp(waitingFor: seconds)
            #expect(hp.fraction >= SessionVitals.floor)
            #expect(hp.fraction <= previous + 1e-9)
            previous = hp.fraction
        }
    }

    @Test("Time running backwards is treated as just now")
    func negativeIsJustNow() {
        #expect(SessionVitals.hp(waitingFor: -120) == (1, .fresh))
    }
}
