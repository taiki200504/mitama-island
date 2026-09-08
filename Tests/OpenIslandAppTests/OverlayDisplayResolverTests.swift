import AppKit
import Testing
@testable import OpenIslandApp

/// `OverlayDisplayResolver.pureFrame` used to be a private method that only
/// ever ran against real `NSScreen` geometry. These tests cover the pure,
/// testable replacement directly — in particular the non-notched
/// (`.floatingPill`) placement math this PR introduces, which floats the
/// panel below the menu bar instead of gluing it to the physical top edge.
struct OverlayDisplayResolverTests {
    private let screenFrame = NSRect(x: 0, y: 0, width: 1_920, height: 1_080)
    private let panelSize = NSSize(width: 648, height: 200)

    @Test
    func notchModeAnchorsToThePhysicalTopEdge() {
        // A built-in notch is part of the bezel — the panel sits flush
        // against the physical top edge, not below the menu bar.
        let visibleFrame = NSRect(x: 0, y: 0, width: 1_920, height: 1_056)

        let frame = OverlayDisplayResolver.pureFrame(
            visibleFrame: visibleFrame,
            screenFrame: screenFrame,
            notchSize: NSSize(width: 200, height: 37),
            panelSize: panelSize,
            mode: .notch
        )

        #expect(frame.maxY == screenFrame.maxY)
        #expect(frame.height == panelSize.height)
    }

    @Test
    func floatingPillModeFloatsBelowTheMenuBar() {
        // The menu bar reserves 24pt on this screen (1080 - 1056), so the
        // panel's top edge should land 6pt further down than that.
        let visibleFrame = NSRect(x: 0, y: 0, width: 1_920, height: 1_056)

        let frame = OverlayDisplayResolver.pureFrame(
            visibleFrame: visibleFrame,
            screenFrame: screenFrame,
            notchSize: nil,
            panelSize: panelSize,
            mode: .floatingPill
        )

        #expect(frame.maxY == visibleFrame.maxY - 6)
        #expect(frame.maxY < screenFrame.maxY)
    }

    @Test
    func widthIsCenteredOnTheScreenAndCappedByTheVisibleFrame() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1_920, height: 1_056)

        let frame = OverlayDisplayResolver.pureFrame(
            visibleFrame: visibleFrame,
            screenFrame: screenFrame,
            notchSize: nil,
            panelSize: panelSize,
            mode: .floatingPill
        )

        #expect(frame.width == panelSize.width)
        #expect(frame.midX == screenFrame.midX)
    }

    @Test
    func widthShrinksToFitANarrowVisibleFrame() {
        // A narrow external display where the panel's preferred width would
        // overflow — the 64pt margin must still be respected.
        let narrowScreenFrame = NSRect(x: 0, y: 0, width: 700, height: 1_080)
        let narrowVisibleFrame = NSRect(x: 0, y: 0, width: 700, height: 1_056)

        let frame = OverlayDisplayResolver.pureFrame(
            visibleFrame: narrowVisibleFrame,
            screenFrame: narrowScreenFrame,
            notchSize: nil,
            panelSize: panelSize,
            mode: .floatingPill
        )

        #expect(frame.width == narrowVisibleFrame.width - 64)
    }
}
