import SwiftUI

/// The surface the settings window sits on.
///
/// The island is a lit panel and the settings window was stock system grey, so
/// the two read as different apps. This puts them on the same ground without
/// replacing a single control: the system widgets keep their behaviour and
/// accessibility, and only what is behind them changes.
private struct SettingsThemeGround: ViewModifier {
    func body(content: Content) -> some View {
        let theme = IslandThemes.current
        content
            .background {
                ZStack {
                    theme.ink
                    // A single wash from the top-left, the way a HUD is lit from
                    // one source. Flat ink reads as an unlit box.
                    LinearGradient(
                        colors: [theme.accent.opacity(0.10), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .ignoresSafeArea()
            }
    }
}

extension View {
    func settingsThemeGround() -> some View {
        modifier(SettingsThemeGround())
    }
}
