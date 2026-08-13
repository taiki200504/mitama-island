import OpenIslandCore
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
            cameraGestureSection
            voiceAnswerSection
            panelSection
            resetSection
        }
    }

    private var cameraGesture: CameraGestureSettings { model.settings.cameraGesture }

    /// Carbon registers a key macOS has already reserved and reports success,
    /// then the key never arrives. Saying so here is the difference between a
    /// shortcut the user can fix and one that is simply dead.
    private var triggerIsClaimed: Bool {
        model.panelHotkeys?.touchlessActivationIsClaimedBySystem ?? false
    }

    /// Filed under shortcuts because a key is what starts it. The camera only
    /// runs inside the few seconds that key opens, so this is a shortcut with a
    /// second step rather than a background watcher.
    private var cameraGestureSection: some View {
        Section {
            SettingsToggleRow(
                title: lang.t("settings.camera.enabled"),
                help: lang.t("settings.camera.enabled.help"),
                isOn: Binding(
                    get: { cameraGesture.isEnabled },
                    set: {
                        cameraGesture.isEnabled = $0
                        model.panelHotkeys?.touchlessActivationEnabled = $0
                        model.panelHotkeys?.startPersistentBindings()
                    }
                )
            )

            if cameraGesture.isEnabled {
                SettingsRow(
                    title: lang.t("settings.camera.trigger"),
                    help: triggerIsClaimed ? lang.t("settings.camera.trigger.claimed") : nil
                ) {
                    ShortcutKeyChip(label: TouchlessActivationTrigger.displayLabel)
                }

                SettingsToggleRow(
                    title: lang.t("settings.camera.answersByPalm"),
                    help: lang.t("settings.camera.answersByPalm.help"),
                    isOn: Binding(
                        get: { cameraGesture.answersByPalm },
                        set: {
                            cameraGesture.answersByPalm = $0
                            model.refreshSustainedCamera()
                        }
                    )
                )
            }
        } header: {
            Text(lang.t("settings.camera.section"))
        } footer: {
            Text(lang.t("settings.camera.section.footer"))
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private var voiceCommand: VoiceCommandSettings { model.settings.voiceCommand }

    private var voiceTriggerIsClaimed: Bool {
        SystemHotkeys.isClaimed(
            keyCode: VoiceAnswerTrigger.keyCode,
            modifiers: VoiceAnswerTrigger.modifiers,
            in: SystemHotkeys.current()
        )
    }

    /// Next to the camera gesture: both are ways of answering the island
    /// without reaching for it, and both are a key plus a few seconds.
    private var voiceAnswerSection: some View {
        Section {
            SettingsToggleRow(
                title: lang.t("settings.voice.enabled"),
                help: lang.t("settings.voice.enabled.help"),
                isOn: Binding(
                    get: { voiceCommand.isEnabled },
                    set: {
                        voiceCommand.isEnabled = $0
                        model.panelHotkeys?.voiceAnswerEnabled = $0
                        model.panelHotkeys?.startPersistentBindings()
                    }
                )
            )

            if voiceCommand.isEnabled {
                SettingsRow(
                    title: lang.t("settings.voice.trigger"),
                    help: voiceTriggerIsClaimed ? lang.t("settings.voice.trigger.claimed") : nil
                ) {
                    ShortcutKeyChip(label: VoiceAnswerTrigger.displayLabel)
                }
            }
        } header: {
            Text(lang.t("settings.voice.section"))
        } footer: {
            Text(lang.t("settings.voice.section.footer"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
