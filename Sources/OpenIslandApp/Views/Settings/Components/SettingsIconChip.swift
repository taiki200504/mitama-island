import SwiftUI

/// A quiet icon in the shared theme accent, used in the sidebar and pane title.
struct SettingsIconChip: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 20

    private var cornerRadius: CGFloat { size * 0.26 }
    private var glyphSize: CGFloat { size * 0.58 }

    var body: some View {
        glyph(IslandThemes.current.accent)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: cornerRadius).fill(IslandThemes.current.accent.opacity(0.08)))
            .accessibilityHidden(true)
    }

    private func glyph(_ colour: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: glyphSize, weight: .semibold))
            .foregroundStyle(colour)
    }
}
