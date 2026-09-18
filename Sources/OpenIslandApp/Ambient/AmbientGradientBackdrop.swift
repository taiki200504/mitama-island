import OpenIslandCore
import SwiftUI

/// A flat wash tied to the time of day — the idle board's backdrop before a
/// video is ever dropped into the ambient folder, and what every screen but
/// the primary one keeps showing even after one is.
///
/// Kept at low saturation on purpose: this sits *behind* the `ink` layer the
/// board already draws over everything, so it only has to read as texture at
/// the very edges, not compete with the clock for attention.
struct AmbientGradientBackdrop: View {
    let phase: TimeOfDayPhase

    var body: some View {
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private var colors: [Color] {
        switch phase {
        case .dawn:
            [V6Palette.ink, SAOGrammar.Palette.accentAmber.opacity(0.35)]
        case .day:
            [V6Palette.ink, SAOGrammar.Palette.systemCyan.opacity(0.30)]
        case .dusk:
            [V6Palette.ink, SAOGrammar.Palette.accentOrange.opacity(0.35)]
        case .night:
            [Color.black, V6Palette.ink]
        }
    }
}
