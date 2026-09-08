import AppKit
import AVFoundation
import OpenIslandCore
import SwiftUI

/// The display pane: where the island sits, how big it gets, and which facts a
/// session row carries.
struct DisplaySettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }
    private var display: DisplaySettings { model.settings.display }
    private var lockScan: LockScanSettings { model.settings.lockScan }
    private var timer: TimerSettings { model.settings.timer }
    private var clipboard: ClipboardSettings { model.settings.clipboard }

    var body: some View {
        SettingsPane(tab: .display) {
            monitorSection
            panelSizeSection
            notchSection
            unlockSection
            sessionCardSection
            shelfSection
            timerSection
            clipboardSection
            diagnosticsSection
        }
    }

    // MARK: Unlock

    private var cameraPermissionDenied: Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted: true
        case .authorized, .notDetermined: false
        @unknown default: false
        }
    }

    private var unlockSection: some View {
        Section(lang.t("settings.display.section.unlock")) {
            SettingsToggleRow(
                title: lang.t("settings.lockScan.enabled"),
                help: lang.t("settings.lockScan.enabled.help"),
                isOn: Binding(
                    get: { lockScan.enabled },
                    set: { lockScan.enabled = $0 }
                )
            )

            SettingsToggleRow(
                title: lang.t("settings.lockScan.usesCamera"),
                help: lang.t("settings.lockScan.usesCamera.help"),
                availability: cameraPermissionDenied
                    ? .unsupported(reasonKey: "settings.lockScan.usesCamera.denied")
                    : .ready,
                isOn: Binding(
                    get: { lockScan.usesCamera },
                    set: { lockScan.usesCamera = $0 }
                )
            )
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

            SettingsPickerRow(
                title: lang.t("settings.display.agentIcon"),
                help: lang.t("settings.display.agentIcon.help"),
                availability: AgentIconLibrary.shared.hasAnyIcon
                    ? .ready
                    : .unsupported(reasonKey: "settings.display.agentIcon.missing"),
                selection: Binding(
                    get: { model.agentIconStyle },
                    set: { model.agentIconStyle = $0 }
                )
            ) {
                ForEach(AgentIconStyle.allCases) { style in
                    Text(lang.t(style.labelKey)).tag(style)
                }
            }

            SettingsToggleRow(
                title: lang.t("settings.display.hideIdleSessions"),
                help: lang.t("settings.display.hideIdleSessions.help"),
                isOn: Binding(
                    get: { display.hideIdleSessions },
                    set: { display.hideIdleSessions = $0 }
                )
            )

            SettingsRow(
                title: lang.t("settings.display.ambient"),
                help: lang.t("settings.display.ambient.help")
            ) {
                Picker("", selection: Binding(
                    get: { display.ambientAfterMinutes },
                    set: {
                        display.ambientAfterMinutes = $0
                        model.startAmbientBoardIfEnabled()
                    }
                )) {
                    Text(lang.t("settings.display.ambient.never")).tag(0)
                    ForEach([3, 5, 10, 20], id: \.self) { minutes in
                        Text(lang.t("settings.display.ambient.minutes", minutes)).tag(minutes)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            SettingsRow(
                title: lang.t("settings.display.ambientBackdrop"),
                help: lang.t("settings.display.ambientBackdrop.help")
            ) {
                Picker("", selection: Binding(
                    get: { model.ambientBackdropPreference },
                    set: { model.ambientBackdropPreference = $0 }
                )) {
                    ForEach(AmbientBackdropPreference.allCases, id: \.self) { preference in
                        Text(lang.t(preference.labelKey)).tag(preference)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            SettingsRow(
                title: lang.t("settings.display.ambientVideoFolder"),
                help: lang.t("settings.display.ambientVideoFolder.help")
            ) {
                Button(ambientVideoFolderButtonTitle) {
                    chooseAmbientVideoFolder()
                }
            }

            SettingsToggleRow(
                title: lang.t("settings.display.showsNextEvent"),
                help: lang.t(
                    display.showsNextEvent && !model.calendar.hasAccess
                        ? "settings.display.showsNextEvent.noAccess"
                        : "settings.display.showsNextEvent.help"
                ),
                isOn: Binding(
                    get: { display.showsNextEvent },
                    set: { isOn in
                        display.showsNextEvent = isOn
                        guard isOn else {
                            model.calendar.stop()
                            return
                        }
                        // Asking here and nowhere else: the dialog arrives
                        // because this switch was just turned on, which is the
                        // only context that explains it.
                        Task { await model.calendar.requestAccessAndStart() }
                    }
                )
            )

            SettingsToggleRow(
                title: lang.t("settings.display.alertsWhenEventStarts"),
                help: lang.t("settings.display.alertsWhenEventStarts.help"),
                isOn: Binding(
                    get: { display.alertsWhenEventStarts },
                    set: { display.alertsWhenEventStarts = $0 }
                )
            )
            .disabled(!display.showsNextEvent)

            SettingsToggleRow(
                title: lang.t("settings.display.completionBanner"),
                help: lang.t("settings.display.completionBanner.help"),
                isOn: Binding(
                    get: { display.completionBanner },
                    set: { display.completionBanner = $0 }
                )
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

    // MARK: Ambient video folder

    private var ambientVideoFolderButtonTitle: String {
        display.ambientVideoFolderPath.isEmpty
            ? lang.t("settings.display.ambientVideoFolder.choose")
            : (display.ambientVideoFolderPath as NSString).lastPathComponent
    }

    private func chooseAmbientVideoFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        display.ambientVideoFolderPath = url.path
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

    // MARK: Shelf

    private var shelfSection: some View {
        Section(lang.t("settings.display.section.shelf")) {
            SettingsPickerRow(
                title: lang.t("settings.display.shelfExpiresAfter"),
                help: lang.t("settings.display.shelfExpiresAfter.help"),
                selection: Binding(
                    get: { model.shelfExpiresAfter },
                    set: { model.shelfExpiresAfter = $0 }
                )
            ) {
                ForEach(ShelfExpiryOption.allCases) { option in
                    Text(lang.t(option.labelKey)).tag(option)
                }
            }
        }
    }

    // MARK: Timer

    private var timerSection: some View {
        Section(lang.t("settings.display.section.timer")) {
            SettingsToggleRow(
                title: lang.t("settings.timer.eyeBreakEnabled"),
                help: lang.t("settings.timer.eyeBreakEnabled.help"),
                isOn: Binding(
                    get: { timer.eyeBreakEnabled },
                    set: { isOn in
                        timer.eyeBreakEnabled = isOn
                        if isOn {
                            model.focusTimer.start(.eyeBreak())
                        } else if case .eyeBreak = model.focusTimer.state.mode {
                            model.focusTimer.reset()
                        }
                    }
                )
            )
            SettingsToggleRow(
                title: lang.t("settings.timer.playsSound"),
                isOn: Binding(get: { timer.playsSound }, set: { timer.playsSound = $0 })
            )
            SettingsToggleRow(
                title: lang.t("settings.timer.autoAdvance"),
                help: lang.t("settings.timer.autoAdvance.help"),
                isOn: Binding(get: { timer.autoAdvance }, set: { timer.autoAdvance = $0 })
            )
        }
    }

    // MARK: Clipboard

    private var clipboardSection: some View {
        Section(lang.t("settings.display.section.clipboard")) {
            SettingsToggleRow(
                title: lang.t("settings.clipboard.enabled"),
                help: lang.t("settings.clipboard.enabled.help"),
                isOn: Binding(
                    get: { clipboard.enabled },
                    set: { isOn in
                        clipboard.enabled = isOn
                        model.applyClipboardEnabled(isOn)
                    }
                )
            )
            SettingsToggleRow(
                title: lang.t("settings.clipboard.persistsToDisk"),
                help: lang.t("settings.clipboard.persistsToDisk.help"),
                isOn: Binding(get: { clipboard.persistsToDisk }, set: { clipboard.persistsToDisk = $0 })
            )
            SettingsToggleRow(
                title: lang.t("settings.clipboard.pastesOnSelect"),
                help: lang.t("settings.clipboard.pastesOnSelect.help"),
                availability: pastesOnSelectAvailability,
                isOn: Binding(get: { clipboard.pastesOnSelect }, set: { clipboard.pastesOnSelect = $0 })
            )
        }
    }

    private var pastesOnSelectAvailability: FeatureAvailability {
        AXIsProcessTrusted() ? .ready : .unsupported(reasonKey: "settings.clipboard.pastesOnSelect.needsAccessibility")
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
