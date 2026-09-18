import SwiftUI

/// Standard frame for a settings pane: the tab's icon chip and title, then the
/// pane's own grouped content beneath it.
///
/// Every pane goes through this so the header never drifts from the sidebar
/// entry that leads to it.
struct SettingsPane<Content: View>: View {
    let tab: SettingsTab
    @ViewBuilder var content: () -> Content

    private var lang: LanguageManager { LanguageManager.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    SettingsIconChip(systemImage: tab.icon, tint: tab.tint, size: 24)
                    // The text-aware variant: a Japanese or Chinese label falls
                    // back to the system face instead of vanishing into a
                    // display font that has no CJK glyphs.
                    Text(tab.label(lang))
                        .saoCaps(size: 18, text: tab.label(lang))
                }
                SAOGaugeShape(fraction: 1)
                    .fill(SAOGrammar.selectionGradient)
                    .frame(width: 96, height: 2)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 6)

            Form {
                content()
            }
            .formStyle(.grouped)
            // The grouped form paints its own grey. Hiding it lets the window's
            // ground show through, so the settings sit on the same surface the
            // island does instead of on a slab of system chrome.
            //
            // The Section slabs on top of it keep the system's own material:
            // `listRowBackground` does not reach them through `.grouped`, and
            // restyling them would mean touching every Section in twelve
            // panes to change something already dark enough to sit here.
            .scrollContentBackground(.hidden)
            .tint(IslandThemes.current.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .navigationTitle(tab.label(lang))
    }
}

/// Shown for a pane whose UI has not been built yet.
///
/// Says so outright rather than presenting an empty pane that reads as broken.
struct SettingsPaneNotBuiltYet: View {
    let tab: SettingsTab

    var body: some View {
        SettingsPane(tab: tab) {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(LanguageManager.shared.t("settings.paneNotBuilt.title"))
                    Text(LanguageManager.shared.t("settings.paneNotBuilt.body"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
    }
}
