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
