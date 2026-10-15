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
        // The panel's own top edge lands exactly at the menu bar's bottom
        // edge — the extra 6pt gap the closed capsule floats by is that
        // pill's own inset *inside* the window, not part of the window's
        // placement (see `IslandPanelView.v6ClosedSurface()`).
        let visibleFrame = NSRect(x: 0, y: 0, width: 1_920, height: 1_056)

        let frame = OverlayDisplayResolver.pureFrame(
            visibleFrame: visibleFrame,
            screenFrame: screenFrame,
            notchSize: nil,
            panelSize: panelSize,
            mode: .floatingPill
        )

        #expect(frame.maxY == visibleFrame.maxY)
        #expect(frame.maxY < screenFrame.maxY)
    }

    @Test
    func topAnchoredYMatchesForBothCallersOnAScreenWithAnAutoHiddenMenuBar() {
        // When the menu bar auto-hides, `visibleFrame.maxY == screenFrame.maxY`
        // — the exact case that used to make the real window frame
        // (`OverlayPanelController.panelFrame`, driven by a `topStatusBarHeight`
        // fallback of 24) disagree with this pure placement math (driven by
        // `visibleFrame` directly). Both now call the same `topAnchoredY`, so
        // they can no longer drift apart regardless of which fallback either
        // side used to take.
        let fullHeightVisibleFrame = screenFrame

        let y = OverlayDisplayResolver.topAnchoredY(
            screenFrame: screenFrame,
            visibleFrame: fullHeightVisibleFrame,
            height: panelSize.height,
            mode: .floatingPill
        )

        #expect(y == screenFrame.maxY - panelSize.height)
    }

    @Test
    func topAnchoredYForNotchModeIgnoresTheVisibleFrame() {
        // The physical notch is part of the bezel — flush with the screen's
        // own top edge regardless of how much the menu bar reserves.
        let visibleFrame = NSRect(x: 0, y: 0, width: 1_920, height: 1_000)

        let y = OverlayDisplayResolver.topAnchoredY(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            height: panelSize.height,
            mode: .notch
        )

        #expect(y == screenFrame.maxY - panelSize.height)
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

    @Test
    func pointerScreenIsFoundAcrossStackedDisplays() {
        // The layout this was found on: a built-in display with two
        // monitors sitting above it.
        let builtIn = NSRect(x: 0, y: 0, width: 1_512, height: 982)
        let left = NSRect(x: -1_119, y: 982, width: 1_920, height: 1_080)
        let right = NSRect(x: 801, y: 982, width: 1_920, height: 1_080)
        let frames = [builtIn, left, right]

        #expect(OverlayDisplayResolver.screenIndex(containing: NSPoint(x: 700, y: 500), in: frames) == 0)
        #expect(OverlayDisplayResolver.screenIndex(containing: NSPoint(x: -500, y: 1_500), in: frames) == 1)
        #expect(OverlayDisplayResolver.screenIndex(containing: NSPoint(x: 2_000, y: 2_062), in: frames) == 2)
        // Pressed against the top of the built-in display, right under the
        // monitor above it: still the built-in one, where its notch is.
        #expect(OverlayDisplayResolver.screenIndex(containing: NSPoint(x: 900, y: 982), in: frames) == 0)
        #expect(OverlayDisplayResolver.screenIndex(containing: NSPoint(x: 5_000, y: 5_000), in: frames) == nil)
    }
}
