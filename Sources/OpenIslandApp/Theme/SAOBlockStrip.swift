import SwiftUI

/// A strip of small square-ish blocks with a gap between them, used for
/// segmented meters. Only the strip's own outer corners round off — the two
/// ends of the first and last cell — so separate cells still read as one
/// rounded bar.
struct SAOBlockStrip: View {
    let cells: Int
    var cellSize: CGSize
    var gap: CGFloat = SAOGrammar.Metric.blockGap
    var color: Color
    var cornerRadius: CGFloat = 2

    var body: some View {
        HStack(spacing: gap) {
            ForEach(0..<max(cells, 0), id: \.self) { index in
                let corners = Self.roundedCorners(index: index, count: cells)
                UnevenRoundedRectangle(
                    topLeadingRadius: corners.contains(.topLeading) ? cornerRadius : 0,
                    bottomLeadingRadius: corners.contains(.bottomLeading) ? cornerRadius : 0,
                    bottomTrailingRadius: corners.contains(.bottomTrailing) ? cornerRadius : 0,
                    topTrailingRadius: corners.contains(.topTrailing) ? cornerRadius : 0
                )
                .fill(color)
                .frame(width: cellSize.width, height: cellSize.height)
            }
        }
    }

    /// Which corners of the cell at `index` (of `count`) round off.
    ///
    /// A single cell rounds all four; otherwise only the leading corners of
    /// the first cell and the trailing corners of the last one do — every
    /// cell in between stays square on all sides since its neighbours cover
    /// what would otherwise be its rounded edge.
    static func roundedCorners(index: Int, count: Int) -> SAOPanelShape.Cuts {
        guard count > 0, (0..<count).contains(index) else { return [] }
        if count == 1 {
            return [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing]
        }
        if index == 0 {
            return [.topLeading, .bottomLeading]
        }
        if index == count - 1 {
            return [.topTrailing, .bottomTrailing]
        }
        return []
    }
}
