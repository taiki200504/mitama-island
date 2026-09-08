import AppKit
import Testing
@testable import OpenIslandApp

/// ⌥-click removes a shelf item on release, without waiting for a drag —
/// unless a drag actually started, in which case the drag wins.
@MainActor
struct ShelfItemDragSourceTests {
    private func mouseEvent(_ type: NSEvent.EventType, modifierFlags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!
    }

    @Test("⌥-click fires the option handler on release")
    func optionClickFiresTheHandlerOnMouseUp() {
        let view = ShelfDragSourceView()
        var didFire = false
        view.onOptionClick = { didFire = true }

        view.mouseDown(with: mouseEvent(.leftMouseDown, modifierFlags: .option))
        #expect(!didFire, "must not fire before the mouse is released")

        view.mouseUp(with: mouseEvent(.leftMouseUp, modifierFlags: .option))
        #expect(didFire)
    }

    @Test("A plain click does not remove anything")
    func plainClickDoesNotFireTheHandler() {
        let view = ShelfDragSourceView()
        var didFire = false
        view.onOptionClick = { didFire = true }

        view.mouseDown(with: mouseEvent(.leftMouseDown, modifierFlags: []))
        view.mouseUp(with: mouseEvent(.leftMouseUp, modifierFlags: []))

        #expect(!didFire)
    }

    // An ⌥-drag that actually starts moving is not covered here: starting a
    // real `NSDraggingSession` needs a window and an event loop, which a
    // headless unit test does not have. `mouseDragged` setting
    // `didBeginDragging` before `mouseUp` checks it is exercised by reading
    // the source in `ShelfItemDragSource.swift` instead.
}
