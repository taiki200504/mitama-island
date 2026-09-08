import AppKit
import Testing
@testable import OpenIslandApp

/// ⌥-click removes a shelf item on the spot, without waiting for a drag.
@MainActor
struct ShelfItemDragSourceTests {
    private func mouseDownEvent(modifierFlags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.mouseEvent(
            with: .leftMouseDown,
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

    @Test("⌥-click fires the option handler")
    func optionClickFiresTheHandler() {
        let view = ShelfDragSourceView()
        var didFire = false
        view.onOptionClick = { didFire = true }

        view.mouseDown(with: mouseDownEvent(modifierFlags: .option))

        #expect(didFire)
    }

    @Test("A plain click does not remove anything")
    func plainClickDoesNotFireTheHandler() {
        let view = ShelfDragSourceView()
        var didFire = false
        view.onOptionClick = { didFire = true }

        view.mouseDown(with: mouseDownEvent(modifierFlags: []))

        #expect(!didFire)
    }
}
