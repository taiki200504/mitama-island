import SwiftUI

/// The rounded-square, filled icon used for every settings tab.
///
/// The reference product does not tint a bare SF Symbol — each tab gets a solid
/// coloured chip with a white glyph on it, in the sidebar and again beside the
/// pane title. Keeping that in one view means the two never drift apart.
struct SettingsIconChip: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 20

    private var cornerRadius: CGFloat { size * 0.26 }
    private var glyphSize: CGFloat { size * 0.58 }

    var body: some View {
        let theme = IslandThemes.current
        Group {
            switch theme.cornerStyle {
            case .rounded:
                filledChip(cornerRadius: cornerRadius)
            case .chamfered:
                // Inverted for the heads-up display: a dark chip with a lit
                // glyph and a hairline edge, rather than a solid colour block.
                // Each tab keeps its own hue, so the sidebar stays as easy to
                // scan — only the way the colour is applied changes.
                litChip(theme: theme)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func filledChip(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(tint.gradient)
            .overlay { glyph(.white) }
    }

    private func litChip(theme: any IslandTheme) -> some View {
        let shape = theme.shape(cornerRadius: cornerRadius * 1.4)
        return shape
            .fill(tint.opacity(0.16))
            .overlay(shape.strokeBorder(tint.opacity(0.65), lineWidth: 1))
            .overlay { glyph(tint) }
            .shadow(color: tint.opacity(0.45), radius: theme.glowRadius)
    }

    private func glyph(_ colour: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: glyphSize, weight: .semibold))
            .foregroundStyle(colour)
    }
}
