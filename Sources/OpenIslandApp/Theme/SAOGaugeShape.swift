import SwiftUI

/// An HP-bar shape: a vertical left edge and a diagonal right edge, the same
/// slope as every other cut in this theme.
///
/// `isTrack` draws the full-width outline (the empty gauge's background);
/// otherwise the shape narrows to `fraction` of the width while keeping the
/// same diagonal at its own trailing edge, so a half-full bar still ends on
/// the theme's signature angle rather than a plain vertical cut.
struct SAOGaugeShape: Shape {
    /// 0 (empty) to 1 (full).
    var fraction: CGFloat
    var isTrack: Bool = false

    var animatableData: CGFloat {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clampedFraction = min(max(0, fraction), 1)
        let width = isTrack ? rect.width : rect.width * clampedFraction
        guard width > 0, rect.height > 0 else { return Path() }

        let dx = min(rect.height * SAOGrammar.Metric.slope, width)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + width - dx, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + width, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
