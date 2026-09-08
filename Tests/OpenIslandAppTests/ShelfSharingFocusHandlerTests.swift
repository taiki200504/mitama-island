import AppKit
import Testing
@testable import OpenIslandApp

/// `ShelfSharingFocusHandler` decides whether to hand focus back once AirDrop
/// or the share sheet is done. Both branches must clear `returnFocusTo` so a
/// stale target never lingers into the next share.
@MainActor
struct ShelfSharingFocusHandlerTests {
    private final class FakeFocusTarget: ShelfFocusTarget {
        var isTerminated: Bool
        private(set) var activateCallCount = 0

        init(isTerminated: Bool) {
            self.isTerminated = isTerminated
        }

        @discardableResult
        func activate(options: NSApplication.ActivationOptions) -> Bool {
            activateCallCount += 1
            return true
        }
    }

    @Test("With nothing to return to, restoring focus is a safe no-op")
    func noReturnTargetClearsCleanly() {
        let handler = ShelfSharingFocusHandler()
        #expect(handler.returnFocusTo == nil)

        handler.restoreFocus()

        #expect(handler.returnFocusTo == nil)
    }

    @Test("A live target is activated and then forgotten")
    func liveTargetIsActivatedAndCleared() {
        let handler = ShelfSharingFocusHandler()
        let target = FakeFocusTarget(isTerminated: false)
        handler.returnFocusTo = target

        handler.restoreFocus()

        #expect(target.activateCallCount == 1)
        #expect(handler.returnFocusTo == nil)
    }

    @Test("A target that quit in the meantime is forgotten without being activated")
    func terminatedTargetIsClearedWithoutActivating() {
        let handler = ShelfSharingFocusHandler()
        let target = FakeFocusTarget(isTerminated: true)
        handler.returnFocusTo = target

        handler.restoreFocus()

        #expect(target.activateCallCount == 0)
        #expect(handler.returnFocusTo == nil)
    }
}
