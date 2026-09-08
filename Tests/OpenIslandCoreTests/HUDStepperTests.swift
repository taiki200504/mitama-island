import Testing
@testable import OpenIslandCore

@Suite("HUDStepper")
struct HUDStepperTests {
    @Test("A coarse press moves by one sixteenth of the range")
    func coarseStepMovesOneSixteenth() {
        let next = HUDStepper.next(level: 0.5, direction: 1, fine: false)
        #expect(abs(next - 0.5625) < 0.0001)
    }

    @Test("A fine press moves by one sixty-fourth of the range")
    func fineStepMovesOneSixtyFourth() {
        let next = HUDStepper.next(level: 0.5, direction: 1, fine: true)
        #expect(abs(next - (0.5 + 1.0 / 64.0)) < 0.0001)
    }

    @Test("Stepping up from the top stays clamped at one")
    func clampsAtTop() {
        #expect(HUDStepper.next(level: 1, direction: 1, fine: false) == 1)
    }

    @Test("Stepping down from the bottom stays clamped at zero")
    func clampsAtBottom() {
        #expect(HUDStepper.next(level: 0, direction: -1, fine: false) == 0)
    }

    @Test("An off-grid level snaps onto the coarse grid rather than drifting")
    func snapsOffGridLevelToCoarseGrid() {
        // 0.4 is not a multiple of 1/16; the nearest coarse stop above it is
        // 7/16 = 0.4375.
        let next = HUDStepper.next(level: 0.4, direction: 1, fine: false)
        #expect(abs(next - 0.4375) < 0.0001)
    }

    @Test("An off-grid level snaps onto the fine grid the same way")
    func snapsOffGridLevelToFineGrid() {
        // 0.4 is not a multiple of 1/64; the nearest fine stop above it is
        // 26/64 = 0.40625.
        let next = HUDStepper.next(level: 0.4, direction: 1, fine: true)
        #expect(abs(next - 0.40625) < 0.0001)
    }

    @Test("Zero segments are lit at the bottom")
    func segmentsAtZero() {
        #expect(HUDStepper.segments(level: 0) == 0)
    }

    @Test("All 16 segments are lit at the top")
    func segmentsAtOne() {
        #expect(HUDStepper.segments(level: 1) == 16)
    }

    @Test("9 of 16 segments are lit at 0.5625")
    func segmentsAtNineSixteenths() {
        #expect(HUDStepper.segments(level: 0.5625) == 9)
    }

    @Test("A level past 1 still reports the full 16 segments rather than overflowing")
    func segmentsClampAboveOne() {
        #expect(HUDStepper.segments(level: 1.5) == 16)
    }

    @Test("A negative level still reports zero segments rather than going negative")
    func segmentsClampBelowZero() {
        #expect(HUDStepper.segments(level: -0.5) == 0)
    }
}
