import SwiftUI

/// The crystal-HUD panel: a rounded rectangle whose selected corners are cut
/// on the diagonal instead of rounded — the signature shape of this theme,
/// echoed at every size from a badge to the opened island's own shell.
struct SAOPanelShape: InsettableShape {
    /// Which corners cut. A corner not in this set is rounded at
    /// `cornerRadius` instead.
    struct Cuts: OptionSet, Sendable {
        let rawValue: Int
        init(rawValue: Int) { self.rawValue = rawValue }

        static let topLeading = Cuts(rawValue: 1 << 0)
        static let topTrailing = Cuts(rawValue: 1 << 1)
        static let bottomLeading = Cuts(rawValue: 1 << 2)
        static let bottomTrailing = Cuts(rawValue: 1 << 3)

        /// Clockwise traversal order, starting top-leading — the order the
        /// path is built in.
        static let allInOrder: [Cuts] = [.topLeading, .topTrailing, .bottomTrailing, .bottomLeading]
    }

    var cornerRadius: CGFloat
    var cuts: Cuts
    /// Δy of a diagonal cut. Δx follows at `cutDepth * SAOGrammar.Metric.slope`.
    var cutDepth: CGFloat
    private var insetAmount: CGFloat

    init(
        cornerRadius: CGFloat = SAOGrammar.Metric.cornerRadius,
        cuts: Cuts = [.topLeading, .bottomTrailing],
        cutDepth: CGFloat = 8,
        insetAmount: CGFloat = 0
    ) {
        self.cornerRadius = cornerRadius
        self.cuts = cuts
        self.cutDepth = cutDepth
        self.insetAmount = insetAmount
    }

    /// Only the cut depth animates. A card resizing its chamfer mid-transition
    /// is the one case this theme actually does; radius and which corners cut
    /// never change on their own.
    var animatableData: CGFloat {
        get { cutDepth }
        set { cutDepth = newValue }
    }

    func inset(by amount: CGFloat) -> SAOPanelShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard rect.width > 0, rect.height > 0 else { return Path() }

        // A cut or radius larger than half the shorter side would send the
        // two edges of a corner past each other, turning the panel into a
        // bowtie.
        let maxOffset = min(rect.width, rect.height) / 2
        let radius = min(max(0, cornerRadius), maxOffset)
        let depth = min(max(0, cutDepth), maxOffset)

        var path = Path()

        // Clockwise from top-leading. A corner's two tangent points sit on
        // its two incident edges — one is where the path arrives (the
        // "entry"), the other where it leaves (the "exit") — and which is
        // which alternates by position: top-leading and bottom-trailing
        // arrive along a vertical edge and leave along a horizontal one;
        // top-trailing and bottom-leading do the reverse. Getting this
        // backwards connects a corner's own two tangent points to the wrong
        // neighbour and draws a line across the shape's interior instead of
        // around its edge.
        for (index, corner) in Cuts.allInOrder.enumerated() {
            let isCut = cuts.contains(corner)
            let (dx, dy): (CGFloat, CGFloat) = isCut
                ? (depth * SAOGrammar.Metric.slope, depth)
                : (radius, radius)
            let tangents = Self.cornerTangents(in: rect, corner: corner, dx: dx, dy: dy)
            let entersVertically = index.isMultiple(of: 2)
            let entry = entersVertically ? tangents.vertical : tangents.horizontal
            let exit = entersVertically ? tangents.horizontal : tangents.vertical

            if index == 0 {
                path.move(to: entry)
            } else {
                path.addLine(to: entry)
            }

            if isCut || radius <= 0 {
                path.addLine(to: exit)
            } else {
                path.addArc(
                    tangent1End: Self.cornerPoint(in: rect, corner: corner),
                    tangent2End: exit,
                    radius: radius
                )
            }
        }

        path.closeSubpath()
        return path
    }

    /// The cut-corner vertex pairs for the requested corners, in clockwise
    /// traversal order, as `[horizontal, vertical, horizontal, vertical, …]`.
    ///
    /// Pure geometry with no `Path` involved, so tests can assert the
    /// Δx = Δy × slope relationship directly instead of poking at a `Path`.
    static func vertices(in rect: CGRect, cuts: Cuts, depth: CGFloat) -> [CGPoint] {
        let maxOffset = min(rect.width, rect.height) / 2
        let clampedDepth = min(max(0, depth), maxOffset)
        var points: [CGPoint] = []
        for corner in Cuts.allInOrder where cuts.contains(corner) {
            let tangents = cornerTangents(
                in: rect,
                corner: corner,
                dx: clampedDepth * SAOGrammar.Metric.slope,
                dy: clampedDepth
            )
            points.append(tangents.horizontal)
            points.append(tangents.vertical)
        }
        return points
    }

    private static func cornerPoint(in rect: CGRect, corner: Cuts) -> CGPoint {
        switch corner {
        case .topLeading: CGPoint(x: rect.minX, y: rect.minY)
        case .topTrailing: CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomTrailing: CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottomLeading: CGPoint(x: rect.minX, y: rect.maxY)
        default: .zero
        }
    }

    /// Which direction each tangent point moves away from the rect's own
    /// corner, along the horizontal and vertical edge respectively.
    private static func signs(for corner: Cuts) -> (x: CGFloat, y: CGFloat) {
        switch corner {
        case .topLeading: (1, 1)
        case .topTrailing: (-1, 1)
        case .bottomTrailing: (-1, -1)
        case .bottomLeading: (1, -1)
        default: (0, 0)
        }
    }

    private static func cornerTangents(
        in rect: CGRect,
        corner: Cuts,
        dx: CGFloat,
        dy: CGFloat
    ) -> (horizontal: CGPoint, vertical: CGPoint) {
        let point = cornerPoint(in: rect, corner: corner)
        let sign = signs(for: corner)
        return (
            horizontal: CGPoint(x: point.x + dx * sign.x, y: point.y),
            vertical: CGPoint(x: point.x, y: point.y + dy * sign.y)
        )
    }
}
