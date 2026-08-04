import SwiftUI

/// Keyboard assignments for the panel and the session switcher.
///
/// The five assignable actions fire for real while the panel is expanded,
/// registered through Carbon so no Accessibility permission is needed and the
/// user keeps typing in their terminal. The three fixed keys below them still
/// require the panel to take focus, which it deliberately does not, so those
/// rows stay marked.
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
            .onChange(of: shortcuts.modifier) { _, newValue in
                model.shortcutHints.start(modifier: newValue)
                model.panelHotkeys?.settingsDidChange(panelIsExpanded: true)
            }

            SettingsRow(
                title: lang.t("settings.shortcuts.hints"),
                help: lang.t("settings.shortcuts.hints.help"),
                availability: model.shortcutHints.hasAccessibilityPermission
                    ? .ready
                    : .unsupported(reasonKey: "settings.shortcuts.hints.noPermission")
            )
        }
    }

    private var switcherSection: some View {
        Section(lang.t("settings.shortcuts.section.switcher")) {
            SettingsRow(
                title: lang.t("settings.shortcuts.openSwitcher"),
                help: lang.t("settings.shortcuts.openSwitcher.help")
            ) {
                ShortcutKeyChip(label: "\(shortcuts.modifier.symbol)`")
            }

            SettingsToggleRow(
                title: lang.t("settings.shortcuts.reverseSwitcher"),
                help: lang.t("settings.shortcuts.reverseSwitcher.help"),
                isOn: Binding(
                    get: { shortcuts.reverseSwitcherEnabled },
                    set: {
                        shortcuts.reverseSwitcherEnabled = $0
                        model.panelHotkeys?.startPersistentBindings()
                    }
                )
            )
        }
    }

    /// Letters this keyboard layout cannot produce, or that two actions share.
    /// Either way the shortcut will not fire, and the row says so.
    private var unresolvable: Set<PanelShortcutAction> {
        Set(model.panelHotkeys?.unresolvableActions() ?? [])
    }

    private var panelSection: some View {
        Section {
            ForEach(PanelShortcutAction.allCases, id: \.self) { action in
                ShortcutAssignmentRow(
                    title: lang.t(action.labelKey),
                    modifier: shortcuts.modifier,
                    keyLabel: shortcuts.key(for: action),
                    onAssign: { shortcuts.setKey($0, for: action) }
                )
                .help(
                    unresolvable.contains(action)
                        ? lang.t("settings.shortcuts.unresolvable")
                        : ""
                )
            }

            ForEach(FixedPanelShortcut.allCases, id: \.self) { fixed in
                ShortcutAssignmentRow(
                    title: lang.t(fixed.labelKey),
                    modifier: fixed.usesModifier ? shortcuts.modifier : nil,
                    keyLabel: fixed.keyLabel,
                    pendingNote: .inPanelTypedKeys
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
