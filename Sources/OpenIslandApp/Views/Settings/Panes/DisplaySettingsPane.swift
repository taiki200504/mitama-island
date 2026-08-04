import SwiftUI

/// The display pane: where the island sits, how big it gets, and which facts a
/// session row carries.
struct DisplaySettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }
    private var display: DisplaySettings { model.settings.display }

    var body: some View {
        SettingsPane(tab: .display) {
            monitorSection
            panelSizeSection
            notchSection
            sessionCardSection
            diagnosticsSection
        }
    }

    // MARK: Monitor

    private var monitorSection: some View {
        Section(lang.t("settings.display.monitor")) {
            SettingsPickerRow(
                title: lang.t("settings.display.position"),
                selection: Binding(
                    get: { model.overlayDisplaySelectionID },
                    set: { model.overlayDisplaySelectionID = $0 }
                )
            ) {
                Text(lang.t("settings.general.automatic")).tag(OverlayDisplayOption.automaticID)
                ForEach(model.overlayDisplayOptions) { option in
                    Text(option.title).tag(option.id)
                }
            }

            SettingsPickerRow(
                title: lang.t("settings.display.layoutMode"),
                help: lang.t(model.menuBarLayout.detailKey),
                selection: Binding(
                    get: { model.menuBarLayout },
                    set: { model.menuBarLayout = $0 }
                )
            ) {
                ForEach(MenuBarLayout.allCases) { layout in
                    Text(lang.t(layout.labelKey)).tag(layout)
                }
            }
        }
    }

    // MARK: Panel size

    private var panelSizeSection: some View {
        Section(lang.t("settings.display.section.panelSize")) {
            SettingsPickerRow(
                title: lang.t("settings.display.contentFontSize"),
                selection: Binding(
                    get: { display.contentFontSize },
                    set: { display.contentFontSize = $0 }
                )
            ) {
                ForEach(DisplaySettings.Defaults.contentFontSizeOptions, id: \.self) { size in
                    Text(size == DisplaySettings.Defaults.contentFontSize
                         ? lang.t("settings.display.contentFontSize.default", points(size))
                         : points(size))
                        .tag(size)
                }
            }

            SettingsSliderRow(
                title: lang.t("settings.display.maxPanelHeight"),
                value: Binding(
                    get: { display.maxPanelHeight },
                    set: { display.maxPanelHeight = $0 }
                ),
                range: DisplaySettings.Defaults.maxPanelHeightRange,
                step: 20,
                defaultValue: DisplaySettings.Defaults.maxPanelHeight,
                format: points
            )

            SettingsSliderRow(
                title: lang.t("settings.display.maxPanelWidth"),
                value: Binding(
                    get: { display.maxPanelWidth },
                    set: { display.maxPanelWidth = $0 }
                ),
                range: DisplaySettings.Defaults.maxPanelWidthRange,
                step: 4,
                defaultValue: DisplaySettings.Defaults.maxPanelWidth,
                format: points
            )

            SettingsSliderRow(
                title: lang.t("settings.display.completionCardHeight"),
                help: lang.t("settings.display.completionCardHeight.help"),
                value: Binding(
                    get: { display.completionCardMaxHeight },
                    set: { display.completionCardMaxHeight = $0 }
                ),
                range: DisplaySettings.Defaults.completionCardMaxHeightRange,
                step: 10,
                defaultValue: DisplaySettings.Defaults.completionCardMaxHeight,
                format: points
            )
        }
    }

    /// Zero reads as "leave it to macOS" rather than a 0pt notch.
    private func notchOverride(_ value: Double) -> String {
        value <= 0 ? lang.t("settings.display.notch.auto") : points(value)
    }

    /// What macOS reports for this screen, so a nudge has something to start from.
    private var measuredNotchDescription: String {
        guard let screen = NSScreen.main else { return "—" }
        let size = screen.measuredNotchSize
        return "\(Int(size.width)) × \(Int(size.height)) pt"
    }

    // MARK: Notch calibration

    private var notchSection: some View {
        Section(lang.t("settings.display.section.notch")) {
            SettingsSliderRow(
                title: lang.t("settings.display.notchHeight"),
                help: lang.t("settings.display.notch.help"),
                value: Binding(
                    get: { display.notchHeightOverride },
                    set: { display.notchHeightOverride = $0 }
                ),
                range: DisplaySettings.Defaults.notchOverrideRange,
                step: 1,
                defaultValue: 0,
                format: notchOverride
            )

            SettingsSliderRow(
                title: lang.t("settings.display.notchWidth"),
                value: Binding(
                    get: { display.notchWidthOverride },
                    set: { display.notchWidthOverride = $0 }
                ),
                range: DisplaySettings.Defaults.notchOverrideRange,
                step: 1,
                defaultValue: 0,
                format: notchOverride
            )

            SettingsRow(
                title: lang.t("settings.display.notch.measured"),
                help: lang.t("settings.display.notch.measured.help")
            ) {
                SettingsValuePill(text: measuredNotchDescription, isDefault: true)
            }
        }
    }

    // MARK: Session card

    private var sessionCardSection: some View {
        Section(lang.t("settings.display.section.sessionCard")) {
            SettingsToggleRow(
                title: lang.t("settings.display.showProjectName"),
                isOn: Binding(get: { display.showProjectName }, set: { display.showProjectName = $0 })
            )
            SettingsToggleRow(
                title: lang.t("settings.display.showWorktree"),
                isOn: Binding(get: { display.showWorktree }, set: { display.showWorktree = $0 })
            )
            SettingsToggleRow(
                title: lang.t("settings.display.showModel"),
                isOn: Binding(get: { display.showModel }, set: { display.showModel = $0 })
            )
            // Reasoning effort is the only one of these the session record does
            // not carry.
            SettingsToggleRow(
                title: lang.t("settings.display.showReasoningEffort"),
                availability: FeatureAvailability(.reasoningEffortMetadata),
                isOn: Binding(
                    get: { display.showReasoningEffort },
                    set: { display.showReasoningEffort = $0 }
                )
            )

            SettingsToggleRow(
                title: lang.t("settings.display.showTasks"),
                help: lang.t("settings.display.showTasks.help"),
                isOn: Binding(get: { display.showTasks }, set: { display.showTasks = $0 })
            )
            SettingsToggleRow(
                title: lang.t("settings.display.showSubagents"),
                help: lang.t("settings.display.showSubagents.help"),
                isOn: Binding(get: { display.showSubagents }, set: { display.showSubagents = $0 })
            )
            SettingsToggleRow(
                title: lang.t("settings.display.showAgentActivity"),
                isOn: Binding(
                    get: { display.showAgentActivity },
                    set: { display.showAgentActivity = $0 }
                )
            )
        }
    }

    // MARK: Diagnostics

    @ViewBuilder
    private var diagnosticsSection: some View {
        if let diagnostics = model.overlayPlacementDiagnostics {
            Section(lang.t("settings.display.diagnostics")) {
                LabeledContent(lang.t("settings.display.currentScreen"), value: diagnostics.targetDescription)
                LabeledContent(lang.t("settings.display.layoutMode"), value: diagnostics.mode.rawValue)
            }
        }
    }

    private func points(_ value: Double) -> String {
        lang.t("settings.points.format", String(Int(value.rounded())))
    }
}
