import SwiftUI

/// v6 closed-island pill: flat top, rounded bottom. Corner radius defaults
/// to `height / 2` so the bottom is a full semicircle.
///
/// Renders as one continuous ink shape regardless of the underlying display:
/// on MacBook it extends past the physical notch (they merge visually since
/// both are black); on external displays it sits as a standalone pill.
struct V6ClosedPillShape: Shape {
    var cornerRadius: CGFloat?

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius ?? rect.height / 2, rect.width / 2, rect.height)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

/// The two colours everything else is built from.
///
/// Kept under the original name so the ~120 call sites did not have to change
/// when themes arrived; the values now come from whichever theme is selected.
@MainActor
enum V6Palette {
    static var ink: Color { IslandThemes.current.ink }
    static var paper: Color { IslandThemes.current.paper }
}
