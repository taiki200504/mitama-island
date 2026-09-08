import SwiftUI
import Testing
@testable import OpenIslandApp

/// The `.floatingPill` top profile replaced a flat-top pill silhouette
/// (`V6ClosedPillShape`) with genuinely rounded top corners, so the opened
/// surface on a non-notched display reads as the same capsule the closed
/// island floats below the menu bar as. These tests check the corner
/// geometry directly, the same way `SAOPanelShapeTests` checks
/// `SAOPanelShape`'s cut corners.
@Suite("Opened island surface shape — floating pill profile")
struct OpenedIslandSurfaceShapeFloatingPillTests {
    private let rect = CGRect(x: 0, y: 0, width: 200, height: 80)

    @Test("Top corners round away instead of cutting a notch silhouette")
    func topCornersRoundInsteadOfNotching() {
        let shape = OpenedIslandSurfaceShape(topProfile: .floatingPill)
        let path = shape.path(in: rect)

        // The exact top corners are excluded by any positive rounding.
        #expect(!path.contains(CGPoint(x: rect.minX, y: rect.minY)))
        #expect(!path.contains(CGPoint(x: rect.maxX, y: rect.minY)))

        // Comfortably past the 12pt top radius on both axes, the fill
        // resumes — a margin generous enough to hold for either a circular
        // or a continuous (squircle) corner curve.
        let inset: CGFloat = 18
        #expect(path.contains(CGPoint(x: rect.minX + inset, y: rect.minY + inset)))
        #expect(path.contains(CGPoint(x: rect.maxX - inset, y: rect.minY + inset)))
    }

    @Test("Bottom corners still follow the animatable bottom radius")
    func bottomCornersFollowTheBottomRadius() {
        let shape = OpenedIslandSurfaceShape(topProfile: .floatingPill, bottomCornerRadius: 20)
        let path = shape.path(in: rect)

        #expect(!path.contains(CGPoint(x: rect.minX, y: rect.maxY)))

        let inset: CGFloat = 26
        #expect(path.contains(CGPoint(x: rect.minX + inset, y: rect.maxY - inset)))
    }
}
