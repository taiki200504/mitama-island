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
            HStack(spacing: 10) {
                SettingsIconChip(systemImage: tab.icon, tint: tab.tint, size: 24)
                Text(tab.label(lang))
                    .font(.title2.weight(.semibold))
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 6)

            Form {
                content()
            }
            .formStyle(.grouped)
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
