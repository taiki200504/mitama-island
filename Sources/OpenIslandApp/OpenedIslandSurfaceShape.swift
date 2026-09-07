import SwiftUI

struct OpenedIslandSurfaceShape: Shape {
    enum TopProfile: Equatable {
        case notch
        case topBar
    }

    /// How deep the crystal-HUD diagonal cut reaches into the notch profile's
    /// two bottom corners. Δx follows at `depth * SAOGrammar.Metric.slope`,
    /// the same angle every other cut in this theme uses.
    static let bottomCutDepth: CGFloat = 10

    var topProfile: TopProfile
    var bottomCornerRadius: CGFloat = NotchShape.openedBottomRadius

    var animatableData: CGFloat {
        get { bottomCornerRadius }
        set { bottomCornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        switch topProfile {
        case .notch:
            let base = NotchShape(
                topCornerRadius: NotchShape.openedTopRadius,
                bottomCornerRadius: bottomCornerRadius
            )
            .path(in: rect)
            return Self.chamferedBottomCorners(of: base, in: rect)
        case .topBar:
            // Left as `V6ClosedPillShape` draws it — same shape the closed
            // pill uses, untouched by the crystal-HUD chamfer.
            return V6ClosedPillShape(cornerRadius: bottomCornerRadius)
                .path(in: rect)
        }
    }

    /// Cuts the two bottom corners of `base` on the diagonal instead of
    /// leaving them rounded.
    ///
    /// Applied on top of `NotchShape`'s own path rather than inside it: that
    /// shape's vertical edges sit inset by `NotchShape.openedTopRadius` from
    /// both sides of `rect` at every height (not just near the top notch
    /// curve), so the cut has to be anchored at that same inset rather than
    /// at the rect's own corners.
    private static func chamferedBottomCorners(of base: Path, in rect: CGRect) -> Path {
        let topInset = NotchShape.openedTopRadius
        let depth = min(bottomCutDepth, rect.height / 2)
        let dx = min(depth * SAOGrammar.Metric.slope, max(0, rect.width / 2 - topInset))
        guard depth > 0, dx > 0 else { return base }

        var leftCut = Path()
        leftCut.move(to: CGPoint(x: rect.minX + topInset, y: rect.maxY - depth))
        leftCut.addLine(to: CGPoint(x: rect.minX + topInset, y: rect.maxY))
        leftCut.addLine(to: CGPoint(x: rect.minX + topInset + dx, y: rect.maxY))
        leftCut.closeSubpath()

        var rightCut = Path()
        rightCut.move(to: CGPoint(x: rect.maxX - topInset - dx, y: rect.maxY))
        rightCut.addLine(to: CGPoint(x: rect.maxX - topInset, y: rect.maxY))
        rightCut.addLine(to: CGPoint(x: rect.maxX - topInset, y: rect.maxY - depth))
        rightCut.closeSubpath()

        return base.subtracting(leftCut).subtracting(rightCut)
    }
}
