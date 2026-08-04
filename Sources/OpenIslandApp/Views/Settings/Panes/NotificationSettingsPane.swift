import SwiftUI

/// Which sessions get to interrupt, and which never reach the island at all.
struct NotificationSettingsPane: View {
    var model: AppModel

    @State private var draftField: SilenceRuleField = .workingDirectory
    @State private var draftMatch: SilenceRuleMatch = .contains
    @State private var draftPattern = ""

    private var lang: LanguageManager { model.lang }
    private var behaviour: BehaviourSettings { model.settings.behaviour }
    private var filters: NotificationFilterSettings { model.settings.notificationFilters }

    var body: some View {
        SettingsPane(tab: .notifications) {
            completionSection
            quietSection
            presetSection
            customSection
            blockedAppsSection
        }
    }

    // MARK: Completion

    private var completionSection: some View {
        Section(lang.t("settings.notifications.section.completion")) {
            SettingsToggleRow(
                title: lang.t("settings.notifications.expandOnCompletion"),
                help: lang.t("settings.notifications.expandOnCompletion.help"),
                isOn: Binding(
                    get: { behaviour.expandOnCompletion },
                    set: { behaviour.expandOnCompletion = $0 }
                )
            )
        }
    }

    // MARK: Quiet scenes

    private var quietSection: some View {
        Section(lang.t("settings.notifications.section.quiet")) {
            SettingsToggleRow(
                title: lang.t("settings.notifications.quiet.focus"),
                help: lang.t("settings.notifications.quiet.focus.help"),
                icon: "moon.fill",
                availability: model.quietScenes.focusDetectionIsAvailable
                    ? FeatureAvailability(.focusModeDetection)
                    : .unsupported(reasonKey: "settings.notifications.quiet.focus.unavailable"),
                isOn: Binding(
                    get: { !behaviour.quietFocusModes.isEmpty },
                    set: { on in
                        for mode in QuietFocusMode.allCases {
                            behaviour.setQuiet(on, during: mode)
                        }
                    }
                )
            )
            SettingsToggleRow(
                title: lang.t("settings.notifications.quiet.screenLocked"),
                help: lang.t("settings.notifications.quiet.screenLocked.help"),
                icon: "lock.fill",
                availability: FeatureAvailability(.screenStateDetection),
                isOn: Binding(
                    get: { behaviour.quietWhenScreenObscured },
                    set: { behaviour.quietWhenScreenObscured = $0 }
                )
            )
            SettingsToggleRow(
                title: lang.t("settings.notifications.quiet.screenShared"),
                help: lang.t("settings.notifications.quiet.screenShared.help"),
                icon: "record.circle",
                availability: FeatureAvailability(.screenCaptureDetection),
                isOn: Binding(
                    get: { behaviour.quietWhenScreenCaptured },
                    set: { behaviour.quietWhenScreenCaptured = $0 }
                )
            )
        }
    }

    // MARK: Built-in filters

    private var presetSection: some View {
        Section(lang.t("settings.notifications.section.presets")) {
            ForEach(SilenceRule.presets) { preset in
                SettingsToggleRow(
                    title: lang.t(preset.presetLabelKey),
                    help: ruleDescription(preset),
                    isOn: Binding(
                        get: { filters.isEnabled(preset) },
                        set: { filters.setEnabled($0, for: preset) }
                    )
                )
            }
        }
    }

    // MARK: Custom filters

    private var customSection: some View {
        Section {
            ForEach(filters.customRules) { rule in
                SettingsRow(title: ruleDescription(rule)) {
                    Button(lang.t("settings.notifications.removeRule")) {
                        filters.removeRule(id: rule.id)
                    }
                    .foregroundStyle(.red)
                }
            }

            if filters.customRules.isEmpty {
                Text(lang.t("settings.notifications.noRules"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            draftRow
        } header: {
            Text(lang.t("settings.notifications.section.custom"))
        } footer: {
            Text(lang.t("settings.notifications.section.custom.footer"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var draftRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("", selection: $draftField) {
                    ForEach(SilenceRuleField.allCases, id: \.self) { field in
                        Text(lang.t(field.labelKey)).tag(field)
                    }
                }
                .labelsHidden()
                .fixedSize()

                Picker("", selection: $draftMatch) {
                    ForEach(SilenceRuleMatch.allCases, id: \.self) { match in
                        Text(lang.t(match.labelKey)).tag(match)
                    }
                }
                .labelsHidden()
                .fixedSize()

                TextField(lang.t("settings.notifications.pattern.placeholder"), text: $draftPattern)
                    .textFieldStyle(.roundedBorder)

                Button(lang.t("settings.notifications.addRule")) {
                    filters.addRule(
                        SilenceRule(field: draftField, match: draftMatch, pattern: draftPattern)
                    )
                    draftPattern = ""
                }
                .disabled(draftPattern.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // Says what the pattern would do before it is committed.
            if !draftPattern.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(lang.t(
                    "settings.notifications.matchCount",
                    String(draftMatchCount)
                ))
                .font(.caption)
                .foregroundStyle(draftMatchCount > 0 ? Color.orange : .secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var draftMatchCount: Int {
        filters.matchCount(
            for: SilenceRule(field: draftField, match: draftMatch, pattern: draftPattern),
            in: model.state.sessions
        )
    }

    private var blockedAppsSection: some View {
        Section {
            SettingsRow(
                title: lang.t("settings.notifications.blockedApps"),
                availability: FeatureAvailability(.launcherAppDetection)
            )
        }
    }

    private func ruleDescription(_ rule: SilenceRule) -> String {
        "\(lang.t(rule.field.labelKey)) \(lang.t(rule.match.labelKey))  \(rule.pattern)"
    }
}
