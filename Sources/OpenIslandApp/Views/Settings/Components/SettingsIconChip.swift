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
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(tint.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: glyphSize, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}
