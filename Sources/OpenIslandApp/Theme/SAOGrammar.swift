import SwiftUI

/// Design tokens for the crystal-HUD grammar: diagonal cuts instead of plain
/// rounding, a tri-line outline, white cards floating over the ink shell, and
/// the orange/amber accent pairing that replaces the old single cyan accent.
///
/// A plain `enum` namespace rather than living on `SAOTheme`: these are pure
/// geometry and colour constants needed from `Shape` types and static helpers
/// that have no theme instance to read from.
enum SAOGrammar {
    enum Palette {
        static let ink = Color(hex: 0x06101E)
        static let paper = Color(hex: 0xE8F7FF)
        static let panelWhite = Color.white
        static let hpLimeStart = Color(hex: 0x96F117)
        static let hpLimeEnd = Color(hex: 0x8DFF0A)
        static let statusYellow = Color(hex: 0xF3F315)
        static let accentOrange = Color(hex: 0xFF7A00)
        static let accentAmber = Color(hex: 0xFFB300)
        static let systemCyan = Color(hex: 0x03A9F4)
        static let danger = Color(hex: 0xE53935)
        /// The outermost ring of `saoOutline`. Bright enough to survive
        /// Increase Contrast or a greyscale display on its own, before the
        /// hairline underneath backs it up.
        static let outlineGlow = Color(red: 1, green: 1, blue: 60 / 255).opacity(0.81)
        static let outlineDark = Color(hex: 0x565653)
        static let hairline = Color(hex: 0x565653)
    }

    enum Metric {
        /// Every diagonal cut in this grammar shares one angle: Δx = Δy × slope.
        static let slope: CGFloat = 0.57
        static let cornerRadius: CGFloat = 6
        static let blockGap: CGFloat = 2
        static let outline = (outer: CGFloat(2.7), mid: CGFloat(3.0), inner: CGFloat(2.3), blur: CGFloat(0.8))
        static let islandOutlineScale: CGFloat = 0.5
    }

    /// The sheen across a white card: brightest along the leading edge,
    /// tapering toward the trailing side.
    static let panelGradient = LinearGradient(
        stops: [
            .init(color: .white.opacity(0.40), location: 0),
            .init(color: .white.opacity(0.40), location: 0.30),
            .init(color: .white.opacity(0.06), location: 1.0),
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let hpGradient = LinearGradient(
        colors: [Palette.hpLimeStart, Palette.hpLimeEnd],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let selectionGradient = LinearGradient(
        colors: [Palette.accentOrange, Palette.accentAmber],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Letter-spacing for a headline set in caps, proportional to size so a
    /// small badge and a large title read as the same typographic choice.
    static func tracking(for size: CGFloat) -> CGFloat {
        size * 0.05
    }
}
