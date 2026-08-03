import SwiftUI

/// The general pane.
///
/// The reference product has no separate "behaviour" pane — when the island
/// opens, when it stays out of the way, and when it folds back all live here,
/// alongside the handful of true system settings. This pane follows that.
struct GeneralSettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }
    private var behaviour: BehaviourSettings { model.settings.behaviour }

    var body: some View {
        SettingsPane(tab: .general) {
            systemSection
            languageSection
            mitamaSection
            expansionSection
            visibilitySection
            dismissalSection
            interactionSection
            mitamaOnlySection
        }
    }

    // MARK: System

    private var systemSection: some View {
        Section(lang.t("settings.section.system")) {
            SettingsToggleRow(
                title: lang.t("settings.general.launchAtLogin"),
                isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.launchAtLoginEnabled = $0 }
                )
            )
        }
    }

    private var languageSection: some View {
        Section(lang.t("settings.general.language")) {
            SettingsPickerRow(
                title: lang.t("settings.general.language"),
                selection: Binding(get: { lang.language }, set: { lang.language = $0 })
            ) {
                Text(lang.t("settings.general.languageSystem")).tag(LanguageManager.AppLanguage.system)
                Text(lang.t("settings.general.languageEnglish")).tag(LanguageManager.AppLanguage.en)
                Text(lang.t("settings.general.languageJapanese")).tag(LanguageManager.AppLanguage.ja)
                Text(lang.t("settings.general.languageChinese")).tag(LanguageManager.AppLanguage.zhHans)
                Text(lang.t("settings.general.languageTraditionalChinese")).tag(LanguageManager.AppLanguage.zhHant)
            }
        }
    }

    /// Lives here until the dedicated mitama pane exists.
    private var mitamaSection: some View {
        Section("mitama") {
            SettingsToggleRow(
                title: lang.t("settings.general.mitamaFeed"),
                help: model.mitamaFeedEnabled && !model.mitamaFeed.isConfigured
                    ? lang.t("settings.general.mitamaFeedMissingConfig")
                    : nil,
                isOn: Binding(
                    get: { model.mitamaFeedEnabled },
                    set: { model.mitamaFeedEnabled = $0 }
                )
            )
        }
    }

    // MARK: Expansion

    private var expansionSection: some View {
        Section(lang.t("settings.general.section.expansion")) {
            SettingsToggleRow(
                title: lang.t("settings.general.expandOnHover"),
                isOn: Binding(
                    get: { behaviour.expandOnHover },
                    set: { behaviour.expandOnHover = $0 }
                )
            )

            SettingsSliderRow(
                title: lang.t("settings.general.hoverDuration"),
                value: Binding(
                    get: { behaviour.hoverDuration },
                    set: { behaviour.hoverDuration = $0 }
                ),
                range: BehaviourSettings.Defaults.hoverDurationRange,
                step: 0.05,
                defaultValue: BehaviourSettings.Defaults.hoverDuration
            ) { seconds in
                String(format: "%.2fs", seconds)
            }
            .disabled(!behaviour.expandOnHover)

            SettingsToggleRow(
                title: lang.t("settings.general.smartSuppression"),
                help: lang.t("settings.general.smartSuppression.help"),
                availability: FeatureAvailability(.foregroundTerminalDetection),
                isOn: Binding(
                    get: { behaviour.smartSuppression },
                    set: { behaviour.smartSuppression = $0 }
                )
            )
        }
    }

    // MARK: Visibility

    private var visibilitySection: some View {
        Section(lang.t("settings.general.section.visibility")) {
            SettingsToggleRow(
                title: lang.t("settings.general.hideInFullscreen"),
                availability: FeatureAvailability(.fullscreenDetection),
                isOn: Binding(
                    get: { behaviour.hideInFullscreen },
                    set: { behaviour.hideInFullscreen = $0 }
                )
            )

            SettingsToggleRow(
                title: lang.t("settings.general.autoHideWhenIdle"),
                availability: FeatureAvailability(.autoHideTimer),
                isOn: Binding(
                    get: { behaviour.autoHideWhenIdle },
                    set: { behaviour.autoHideWhenIdle = $0 }
                )
            )
        }
    }

    // MARK: Dismissal

    private var dismissalSection: some View {
        Section(lang.t("settings.general.section.dismissal")) {
            SettingsToggleRow(
                title: lang.t("settings.general.autoCollapse"),
                isOn: Binding(
                    get: { behaviour.autoCollapseOnLeave },
                    set: { behaviour.autoCollapseOnLeave = $0 }
                )
            )

            SettingsPickerRow(
                title: lang.t("settings.general.autoRevealDwell"),
                help: lang.t("settings.general.autoRevealDwell.help"),
                selection: Binding(
                    get: { behaviour.autoRevealDwell },
                    set: { behaviour.autoRevealDwell = $0 }
                )
            ) {
                ForEach(BehaviourSettings.Defaults.autoRevealDwellOptions, id: \.self) { seconds in
                    Text(lang.t("settings.seconds.format", String(Int(seconds)))).tag(seconds)
                }
            }

            SettingsToggleRow(
                title: lang.t("settings.general.dismissOnOutsideClick"),
                availability: FeatureAvailability(.outsideClickDetection),
                isOn: Binding(
                    get: { behaviour.dismissOnOutsideClick },
                    set: { behaviour.dismissOnOutsideClick = $0 }
                )
            )
        }
    }

    // MARK: Interaction

    private var interactionSection: some View {
        Section(lang.t("settings.general.section.interaction")) {
            SettingsToggleRow(
                title: lang.t("settings.general.disableClickToJump"),
                help: lang.t("settings.general.disableClickToJump.help"),
                isOn: Binding(
                    get: { behaviour.disableClickToJump },
                    set: { behaviour.disableClickToJump = $0 }
                )
            )

            SettingsPickerRow(
                title: lang.t("settings.general.idleCleanup"),
                help: lang.t("settings.general.idleCleanup.help"),
                availability: FeatureAvailability(.idleSessionCleanup),
                selection: Binding(
                    get: { behaviour.idleSessionCleanup },
                    set: { behaviour.idleSessionCleanup = $0 }
                )
            ) {
                ForEach(IdleSessionCleanup.allCases, id: \.self) { option in
                    Text(lang.t(option.labelKey)).tag(option)
                }
            }
        }
    }

    // MARK: Mitama-only

    private var mitamaOnlySection: some View {
        Section(lang.t("settings.general.section.mitamaOnly")) {
            SettingsToggleRow(
                title: lang.t("settings.general.showDockIcon"),
                isOn: Binding(get: { model.showDockIcon }, set: { model.showDockIcon = $0 })
            )
            SettingsToggleRow(
                title: lang.t("settings.general.hapticFeedback"),
                isOn: Binding(
                    get: { model.hapticFeedbackEnabled },
                    set: { model.hapticFeedbackEnabled = $0 }
                )
            )
            SettingsToggleRow(
                title: lang.t("settings.general.completionReply"),
                isOn: Binding(
                    get: { model.completionReplyEnabled },
                    set: { model.completionReplyEnabled = $0 }
                )
            )
            SettingsToggleRow(
                title: lang.t("settings.general.suppressFrontmostNotifications"),
                isOn: Binding(
                    get: { model.suppressFrontmostNotifications },
                    set: { model.suppressFrontmostNotifications = $0 }
                )
            )
        }
    }
}
