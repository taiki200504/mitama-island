import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Lock-scan sequence")
struct LockScanSequenceTests {
    @Test("Boundaries: 0 / 0.6 / 1.4 / 2.2")
    func phaseBoundaries() {
        #expect(LockScanSequence.phase(at: 0) == .scanning)
        #expect(LockScanSequence.phase(at: 0.59) == .scanning)
        #expect(LockScanSequence.phase(at: 0.6) == .confirmed)
        #expect(LockScanSequence.phase(at: 1.39) == .confirmed)
        #expect(LockScanSequence.phase(at: 1.4) == .greeting)
        #expect(LockScanSequence.phase(at: 2.19) == .greeting)
        #expect(LockScanSequence.phase(at: 2.2) == .done)
        #expect(LockScanSequence.phase(at: 10) == .done)
    }

    @Test("Ring progress runs 0...1 across the scanning window and holds at 1 after")
    func ringProgressMonotonic() {
        #expect(LockScanSequence.ringProgress(at: 0) == 0)
        #expect(LockScanSequence.ringProgress(at: LockScanSequence.confirmedAt) == 1)
        #expect(LockScanSequence.ringProgress(at: LockScanSequence.duration) == 1)

        var previous = 0.0
        var sample = 0.0
        while sample <= LockScanSequence.confirmedAt {
            let progress = LockScanSequence.ringProgress(at: sample)
            #expect(progress >= previous)
            #expect(progress >= 0 && progress <= 1)
            previous = progress
            sample += 0.05
        }
    }

    /// Negative elapsed can only come from a clock that moved backwards —
    /// same discipline as `LinkstartSequence`: treat it as the beginning
    /// rather than a state the view has no drawing for.
    @Test("Time before the beginning stays in the scanning phase")
    func negativeTimeIsScanning() {
        #expect(LockScanSequence.phase(at: -1) == .scanning)
        #expect(LockScanSequence.ringProgress(at: -1) == 0)
    }

    @Test("Total duration is 2.2s")
    func duration() {
        #expect(LockScanSequence.duration == 2.2)
    }
}
