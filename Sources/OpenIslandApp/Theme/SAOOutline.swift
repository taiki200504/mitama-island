import SwiftUI

extension View {
    /// The crystal-HUD triple outline: an outer glow, a bright mid line, a
    /// dark inner line, and — always — a 1pt hairline innermost, so the edge
    /// still reads under Increase Contrast or on a greyscale display even if
    /// every colour above it washes out.
    func saoOutline<S: InsettableShape>(
        _ shape: S,
        scale: CGFloat = SAOGrammar.Metric.islandOutlineScale
    ) -> some View {
        let metrics = SAOGrammar.Metric.outline
        return self
            .overlay(
                shape
                    .stroke(SAOGrammar.Palette.outlineGlow, lineWidth: metrics.outer * scale)
                    .blur(radius: metrics.blur * scale)
            )
            .overlay(
                shape.stroke(Color.white, lineWidth: metrics.mid * scale)
            )
            .overlay(
                shape.stroke(SAOGrammar.Palette.outlineDark, lineWidth: metrics.inner * scale)
            )
            .overlay(
                shape.stroke(SAOGrammar.Palette.hairline, lineWidth: 1)
            )
    }

    /// The white card background + triple outline shared by the approval,
    /// question and completion cards: an opaque white base under the theme's
    /// sheen gradient, forced to light colour scheme so `Color.primary` /
    /// `.secondary` and system controls resolve dark against it even though
    /// the panel around the card always forces `.preferredColorScheme(.dark)`.
    func saoCard(cornerRadius: CGFloat = 10, cutDepth: CGFloat = 8) -> some View {
        let shape = SAOPanelShape(cornerRadius: cornerRadius, cutDepth: cutDepth)
        return self
            .background(
                ZStack {
                    shape.fill(SAOGrammar.Palette.panelWhite)
                    shape.fill(SAOGrammar.panelGradient)
                }
            )
            .saoOutline(shape)
            .environment(\.colorScheme, .light)
    }
}
