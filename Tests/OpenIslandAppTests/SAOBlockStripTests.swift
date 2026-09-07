import Testing
@testable import OpenIslandApp

@Suite("SAO block strip")
struct SAOBlockStripTests {
    @Test("The first cell rounds only its leading corners")
    func firstCellRoundsLeadingCorners() {
        let corners = SAOBlockStrip.roundedCorners(index: 0, count: 4)
        #expect(corners == [.topLeading, .bottomLeading])
    }

    @Test("A middle cell has no rounded corners")
    func middleCellIsSquare() {
        let corners = SAOBlockStrip.roundedCorners(index: 1, count: 4)
        #expect(corners.isEmpty)
    }

    @Test("The last cell rounds only its trailing corners")
    func lastCellRoundsTrailingCorners() {
        let corners = SAOBlockStrip.roundedCorners(index: 3, count: 4)
        #expect(corners == [.topTrailing, .bottomTrailing])
    }

    @Test("A single cell rounds every corner")
    func singleCellRoundsEveryCorner() {
        let corners = SAOBlockStrip.roundedCorners(index: 0, count: 1)
        #expect(corners == [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing])
    }

    @Test("An out-of-range index rounds nothing")
    func outOfRangeIndexIsEmpty() {
        #expect(SAOBlockStrip.roundedCorners(index: 5, count: 4).isEmpty)
        #expect(SAOBlockStrip.roundedCorners(index: 0, count: 0).isEmpty)
    }
}
