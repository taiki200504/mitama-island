import Testing
@testable import OpenIslandCore

struct FingerAimTests {
    @Test
    func aHighHandMeansTheTopRow() {
        #expect(FingerAim.rowIndex(normalizedY: 0.70, rowCount: 4) == 0)
        #expect(FingerAim.rowIndex(normalizedY: 0.30, rowCount: 4) == 3)
    }

    @Test
    func reachingBeyondTheBandStillMeansTheEndOfTheList() {
        // Standing up should not mean "nothing" — it means the top.
        #expect(FingerAim.rowIndex(normalizedY: 0.99, rowCount: 3) == 0)
        #expect(FingerAim.rowIndex(normalizedY: 0.01, rowCount: 3) == 2)
    }

    @Test
    func theBandIsSplitEvenlyBetweenTheRows() {
        // Four rows across 0.30...0.70 — each row owns 0.1 of the band.
        #expect(FingerAim.rowIndex(normalizedY: 0.65, rowCount: 4) == 0)
        #expect(FingerAim.rowIndex(normalizedY: 0.55, rowCount: 4) == 1)
        #expect(FingerAim.rowIndex(normalizedY: 0.45, rowCount: 4) == 2)
        #expect(FingerAim.rowIndex(normalizedY: 0.35, rowCount: 4) == 3)
    }

    @Test
    func nothingToAimAt() {
        #expect(FingerAim.rowIndex(normalizedY: 0.5, rowCount: 0) == nil)
        #expect(FingerAim.rowIndex(normalizedY: 0.99, rowCount: 1) == 0)
    }
}
