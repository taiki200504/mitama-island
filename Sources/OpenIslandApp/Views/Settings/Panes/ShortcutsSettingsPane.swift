import SwiftUI

/// Keyboard assignments for the panel and the session switcher.
///
/// Assignments are stored and editable now; nothing fires them yet, because the
/// panel has no key handling and no system-wide hotkey is registered. Every row
/// says so rather than looking live.
struct ShortcutsSettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }
    private var shortcuts: ShortcutSettings { model.settings.shortcuts }

    var body: some View {
        SettingsPane(tab: .shortcuts) {
            globalSection
            switcherSection
            panelSection
            resetSection
        }
    }

    private var globalSection: some View {
        Section(lang.t("settings.shortcuts.section.global")) {
            SettingsToggleRow(
                title: lang.t("settings.shortcuts.enabled"),
                help: lang.t("settings.shortcuts.enabled.help"),
                pendingNote: .panelKeyHandling,
                isOn: Binding(
                    get: { shortcuts.keyboardShortcutsEnabled },
                    set: { shortcuts.keyboardShortcutsEnabled = $0 }
                )
            )

            SettingsPickerRow(
                title: lang.t("settings.shortcuts.modifier"),
                help: lang.t("settings.shortcuts.modifier.help"),
                selection: Binding(
                    get: { shortcuts.modifier },
                    set: { shortcuts.modifier = $0 }
                )
            ) {
                ForEach(ShortcutModifier.allCases, id: \.self) { modifier in
                    Text("\(modifier.symbol)  \(lang.t(modifier.labelKey))").tag(modifier)
                }
            }
        }
    }

    private var switcherSection: some View {
        Section(lang.t("settings.shortcuts.section.switcher")) {
            SettingsRow(
                title: lang.t("settings.shortcuts.openSwitcher"),
                help: lang.t("settings.shortcuts.openSwitcher.help"),
                availability: FeatureAvailability(.switcherPanel)
            )

            SettingsToggleRow(
                title: lang.t("settings.shortcuts.reverseSwitcher"),
                help: lang.t("settings.shortcuts.reverseSwitcher.help"),
                pendingNote: .switcherPanel,
                isOn: Binding(
                    get: { shortcuts.reverseSwitcherEnabled },
                    set: { shortcuts.reverseSwitcherEnabled = $0 }
                )
            )
        }
    }

    private var panelSection: some View {
        Section {
            ForEach(PanelShortcutAction.allCases, id: \.self) { action in
                ShortcutAssignmentRow(
                    title: lang.t(action.labelKey),
                    modifier: shortcuts.modifier,
                    keyLabel: shortcuts.key(for: action),
                    pendingNote: .panelKeyHandling,
                    onAssign: { shortcuts.setKey($0, for: action) }
                )
            }

            ForEach(FixedPanelShortcut.allCases, id: \.self) { fixed in
                ShortcutAssignmentRow(
                    title: lang.t(fixed.labelKey),
                    modifier: fixed.usesModifier ? shortcuts.modifier : nil,
                    keyLabel: fixed.keyLabel,
                    pendingNote: .panelKeyHandling
                )
            }
        } header: {
            Text(lang.t("settings.shortcuts.section.panel"))
        } footer: {
            Text(lang.t("settings.shortcuts.section.panel.footer"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var resetSection: some View {
        Section {
            Button(lang.t("settings.shortcuts.reset")) {
                shortcuts.resetToDefaults()
            }
            .disabled(!shortcuts.isCustomised)
        }
    }
}
