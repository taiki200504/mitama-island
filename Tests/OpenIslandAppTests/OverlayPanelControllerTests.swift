import AppKit
import Testing
@testable import OpenIslandApp

struct OverlayPanelControllerTests {
    /// The island only opens itself for a drag that is carrying files — a
    /// window being moved past the notch must not make it jump out.
    @Test @MainActor
    func onlyFileDragsCountAsSomethingToOpenFor() {
        let pasteboard = NSPasteboard(name: .drag)

        pasteboard.clearContents()
        pasteboard.writeObjects(["not a file" as NSString])
        #expect(!OverlayPanelController.draggedItemsAreFiles())

        pasteboard.clearContents()
        pasteboard.writeObjects([URL(fileURLWithPath: "/tmp/notes.md") as NSURL])
        #expect(OverlayPanelController.draggedItemsAreFiles())

        pasteboard.clearContents()
    }

    @Test
    func closedSurfaceRectCentersOnNotch() {
        let notchRect = NSRect(x: 200, y: 900, width: 200, height: 38)
        let closedWidth: CGFloat = 320

        let rect = OverlayPanelController.closedSurfaceRect(
            notchRect: notchRect,
            closedWidth: closedWidth
        )

        // Centered on notch midX (300), width 320
        #expect(rect.minX == 140)
        #expect(rect.minY == 900)
        #expect(rect.width == 320)
        #expect(rect.height == 38)
    }

    @Test
    func closedSurfaceRectHitTestingBoundary() {
        let notchRect = NSRect(x: 400, y: 1_000, width: 200, height: 38)
        let closedWidth: CGFloat = 420

        let rect = OverlayPanelController.closedSurfaceRect(
            notchRect: notchRect,
            closedWidth: closedWidth
        )

        #expect(rect.contains(NSPoint(x: rect.minX + 2, y: rect.midY)))
        #expect(rect.contains(NSPoint(x: rect.maxX - 2, y: rect.midY)))
        #expect(!rect.contains(NSPoint(x: rect.minX - 1, y: rect.midY)))
        #expect(!rect.contains(NSPoint(x: rect.maxX + 1, y: rect.midY)))
    }

    @Test
    func edgeInclusiveHitTestingTreatsMaxBoundaryAsInside() {
        let rect = NSRect(x: 100, y: 200, width: 224, height: 8)
        #expect(OverlayPanelController.rectContainsIncludingEdges(rect, point: NSPoint(x: 150, y: 208)))
        #expect(OverlayPanelController.rectContainsIncludingEdges(rect, point: NSPoint(x: 324, y: 205)))
        #expect(!OverlayPanelController.rectContainsIncludingEdges(rect, point: NSPoint(x: 325, y: 205)))
        #expect(!OverlayPanelController.rectContainsIncludingEdges(rect, point: NSPoint(x: 150, y: 209)))
    }

    @Test
    func notchedDisplayClosedWidthWrapsPhysicalNotchWithFixedReserve() {
        // MacBook layout: outer width = bleed + physical notch + bleed.
        let width = OverlayPanelController.closedPanelWidth(
            notchWidth: 224,
            isNotchedDisplay: true,
            notchStatus: .closed
        )
        #expect(width == 224 + (OverlayPanelController.closedPillSideBleed * 2))
    }

    @Test
    func externalDisplayClosedWidthFollowsIntrinsicContentPlusHitSlop() {
        // v6 external layout: the floating capsule's hit area follows its
        // real content width (plus a little slop per side) instead of a
        // fixed guess, so a long waiting-agent name still gets a hit area
        // that matches what's actually drawn.
        let width = OverlayPanelController.closedPanelWidth(
            notchWidth: 0,
            isNotchedDisplay: false,
            intrinsicContentWidth: 140,
            notchStatus: .closed
        )
        #expect(width == 140 + (IslandChromeMetrics.floatingPillHitPadding * 2))
    }

    @Test
    func externalDisplayClosedWidthFloorsAtTheCapsuleMinimum() {
        // A near-empty pill (idle glyph only) must not shrink the hit area
        // below the capsule's own rendered minimum width.
        let width = OverlayPanelController.closedPanelWidth(
            notchWidth: 0,
            isNotchedDisplay: false,
            intrinsicContentWidth: 10,
            notchStatus: .closed
        )
        #expect(width == IslandChromeMetrics.floatingPillMinWidth)
    }

    @Test
    func floatingClosedSurfaceRectSitsBelowTheMenuBarCenteredOnScreen() {
        let screenFrame = NSRect(x: 100, y: 0, width: 1_920, height: 1_080)
        let visibleFrame = NSRect(x: 100, y: 0, width: 1_920, height: 1_056)

        let rect = OverlayPanelController.floatingClosedSurfaceRect(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            width: 160,
            height: 30
        )

        #expect(rect.width == 160)
        #expect(rect.height == 30)
        #expect(rect.midX == screenFrame.midX)
        // Floats `floatingPillGap` below the menu bar's bottom edge, not
        // flush against the physical top edge.
        #expect(rect.maxY == visibleFrame.maxY - IslandChromeMetrics.floatingPillGap)
    }

    @Test
    func poppingStatusAddsHoverBudget() {
        let width = OverlayPanelController.closedPanelWidth(
            notchWidth: 224,
            isNotchedDisplay: true,
            notchStatus: .popping
        )
        #expect(width == 224 + (OverlayPanelController.closedPillSideBleed * 2) + 18)
    }

    @Test
    func clickOpensActivateThePanel() {
        #expect(OverlayPanelController.shouldActivatePanel(for: .click))
    }

    @Test
    func passiveOpensDoNotActivateThePanel() {
        #expect(!OverlayPanelController.shouldActivatePanel(for: .hover))
        #expect(!OverlayPanelController.shouldActivatePanel(for: .notification))
        #expect(!OverlayPanelController.shouldActivatePanel(for: .boot))
        #expect(!OverlayPanelController.shouldActivatePanel(for: nil))
    }

    // MARK: - islandClosedHeight

    @Test
    func islandClosedHeightClampsToNotchHeightWhenSmallerThanMenuBar() {
        // Simulates MacBook Air M2: physical notch ≈ 34 pt, menu bar reserved ≈ 37 pt.
        // Must return 34 (the smaller value) so the island sits flush with the notch.
        let height = NSScreen.computeIslandClosedHeight(safeAreaInsetsTop: 34, topStatusBarHeight: 37)
        #expect(height == 34)
    }

    @Test
    func islandClosedHeightUsesNotchHeightEvenWhenMenuBarIsShorter() {
        // When menu bar reserved < notch (e.g. auto-hide menu bar), the island must
        // still match the physical notch height to avoid a visible gap.
        let height = NSScreen.computeIslandClosedHeight(safeAreaInsetsTop: 37, topStatusBarHeight: 34)
        #expect(height == 37)
    }

    @Test
    func islandClosedHeightFallsBackToMenuBarHeightOnNonNotchScreen() {
        // Non-notch screen: safeAreaInsets.top == 0, fall back to topStatusBarHeight.
        let height = NSScreen.computeIslandClosedHeight(safeAreaInsetsTop: 0, topStatusBarHeight: 24)
        #expect(height == 24)
    }
}
