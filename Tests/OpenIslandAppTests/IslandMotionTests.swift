import SwiftUI
import Testing
@testable import OpenIslandApp

@Suite("Island motion")
struct IslandMotionTests {
    /// Reduce Motion has to win over whatever curve was asked for, every
    /// time — a forgotten call site is how a spring survives the setting.
    @Test("Reduce Motion replaces any animation with a short plain fade")
    func reducedMotionReplacesTheAnimation() {
        let resolved = IslandMotion.pure(reduces: true, IslandMotion.open)
        #expect("\(resolved)" == "\(Animation.easeOut(duration: 0.12))")
    }

    @Test("Reduce Motion off leaves the animation untouched")
    func fullMotionPassesThrough() {
        let resolved = IslandMotion.pure(reduces: false, IslandMotion.bandChange)
        #expect("\(resolved)" == "\(IslandMotion.bandChange)")
    }

    /// Every distinct moment gets its own curve — two of these silently
    /// collapsing to the same value would mean one call site is dead.
    @Test("The named curves are not all secretly the same value")
    func curvesAreDistinctEnough() {
        let curves: [Animation] = [
            IslandMotion.open, IslandMotion.close, IslandMotion.pop,
            IslandMotion.bandChange, IslandMotion.hover,
            IslandMotion.selectionSweep, IslandMotion.glowPulse,
            IslandMotion.rowPhase, IslandMotion.modalIn, IslandMotion.modalOut,
        ]
        #expect(Set(curves.map { "\($0)" }).count >= 8)
    }

    @Test("The pop hold matches what the coordinator schedules against")
    func popHoldIsAPositiveDuration() {
        #expect(IslandMotion.popHold == 0.3)
    }
}
