import SwiftUI

/// A rectangle with two opposite corners cut on the diagonal.
///
/// Top-left and bottom-right, not all four: cutting every corner reads as an
/// octagon, while cutting a diagonal pair reads as a panel that was sliced —
/// which is the heads-up-display look this theme is after.
struct ChamferedRectangle: Shape {
    /// How far along each edge the cut starts.
    var cut: CGFloat

    func path(in rect: CGRect) -> Path {
        // A cut larger than half the shorter side would make the two diagonals
        // cross, turning the panel into a bowtie.
        let cut = min(cut, min(rect.width, rect.height) / 2)
        guard cut > 0 else { return Path(rect) }

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cut))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
        path.closeSubpath()
        return path
    }
}


/// The one shape every card, button and badge in the island uses.
///
/// Always chamfered — the two opposite diagonal cuts are the SAO theme's
/// signature shape, and there is only one theme to draw now.
///
/// Insettable rather than `AnyShape` so `strokeBorder` keeps working: a plain
/// `stroke` straddles the edge and bleeds half a line width outside the fill,
/// which shows up as a fuzzy halo on every panel.
///
/// A compatibility wrapper around ``SAOPanelShape`` rather than its own
/// geometry: the crystal-HUD grammar's cut is asymmetric (Δx = Δy × slope,
/// not a 45° diagonal), and routing every one of the 20+
/// `theme.shape(cornerRadius:)` call sites onto that new shape directly would
/// have been a far larger change than this indirection.
struct IslandPanelShape: InsettableShape {
    var cornerRadius: CGFloat
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: inset, dy: inset)
        let effectiveRadius = max(0, cornerRadius - inset)
        return SAOPanelShape(
            cornerRadius: min(effectiveRadius, SAOGrammar.Metric.cornerRadius),
            cuts: [.topLeading, .bottomTrailing],
            cutDepth: max(SAOGrammar.Metric.cornerRadius, effectiveRadius)
        ).path(in: insetRect)
    }

    func inset(by amount: CGFloat) -> IslandPanelShape {
        var copy = self
        copy.inset += amount
        return copy
    }
}
