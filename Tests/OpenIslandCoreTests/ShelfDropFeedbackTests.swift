import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Shelf drop feedback")
struct ShelfDropFeedbackTests {
    @Test("Nothing hovering is idle")
    func nothingHoveringIsIdle() {
        #expect(ShelfDropFeedback.state(hoveringCount: 0) == .idle)
    }

    @Test("A hover with no size information invites")
    func hoverWithUnknownSizeInvites() {
        #expect(ShelfDropFeedback.state(hoveringCount: 2) == .invited(count: 2))
    }

    @Test("A hover that would fit invites")
    func hoverThatFitsInvites() {
        let state = ShelfDropFeedback.state(hoveringCount: 1, addingBytes: 1024, over: [])
        #expect(state == .invited(count: 1))
    }

    @Test("A hover that would overflow the shelf is refused up front")
    func hoverThatOverflowsIsRefused() {
        let huge = ShelfLedger.maximumItemBytes + 1
        let state = ShelfDropFeedback.state(hoveringCount: 1, addingBytes: huge, over: [])
        #expect(state == .refused(.tooLarge(byteSize: huge)))
    }
}
