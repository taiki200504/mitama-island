import AppKit
import ApplicationServices
import AVFoundation
import OpenIslandCore
import SwiftUI

/// The island pane: one short group per module that lives on the island —
/// unlock, shelf, timer, clipboard, now playing, system HUD. Each keeps to a few rows so
/// a new module adds a group here rather than growing the display pane.
struct IslandSettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }
    private var lockScan: LockScanSettings { model.settings.lockScan }
    private var timer: TimerSettings { model.settings.timer }
    private var clipboard: ClipboardSettings { model.settings.clipboard }
    private var nowPlaying: NowPlayingSettings { model.settings.nowPlaying }
    private var hud: HUDSettings { model.settings.hud }

    var body: some View {
        SettingsPane(tab: .island) {
            unlockSection
            shelfSection
            timerSection
            clipboardSection
            nowPlayingSection
            hudSection
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

    // MARK: Now playing

    private var nowPlayingSection: some View {
        Section(lang.t("settings.display.section.nowPlaying")) {
            SettingsToggleRow(
                title: lang.t("settings.nowPlaying.enabled"),
                help: lang.t("settings.nowPlaying.enabled.help"),
                availability: model.nowPlaying.isAvailable
                    ? .ready
                    : .unsupported(reasonKey: "settings.nowPlaying.adapterUnavailable"),
                isOn: Binding(
                    get: { nowPlaying.enabled },
                    set: { isOn in
                        nowPlaying.enabled = isOn
                        if isOn {
                            model.nowPlaying.start()
                        } else {
                            model.nowPlaying.stop()
                        }
                    }
                )
            )
            SettingsToggleRow(
                title: lang.t("settings.nowPlaying.showsInClosedIsland"),
                isOn: Binding(get: { nowPlaying.showsInClosedIsland }, set: { nowPlaying.showsInClosedIsland = $0 })
            )
            SettingsToggleRow(
                title: lang.t("settings.nowPlaying.sneakPeekOnTrackChange"),
                isOn: Binding(get: { nowPlaying.sneakPeekOnTrackChange }, set: { nowPlaying.sneakPeekOnTrackChange = $0 })
            )
        }
    }

    // MARK: System HUD

    private var hudAccessibilityDenied: Bool {
        hud.replacesSystem && !AXIsProcessTrusted()
    }

    private var hudSection: some View {
        Section(lang.t("settings.display.section.hud")) {
            SettingsToggleRow(
                title: lang.t("settings.hud.replacesSystem"),
                help: lang.t("settings.hud.replacesSystem.help"),
                availability: hudAccessibilityDenied
                    ? .unsupported(reasonKey: "settings.hud.replacesSystem.denied")
                    : .ready,
                isOn: Binding(
                    get: { hud.replacesSystem },
                    set: { isOn in
                        hud.replacesSystem = isOn
                        guard isOn else {
                            model.systemHUD.stop()
                            return
                        }
                        // Asking here and nowhere else, the same rule
                        // `showsNextEvent` follows above: a permission dialog
                        // only makes sense right after the switch that caused it.
                        //
                        // `kAXTrustedCheckOptionPrompt` itself is a global
                        // `var` the SDK does not mark concurrency-safe; its
                        // value is this fixed string, so the string literal
                        // sidesteps that without changing what gets asked.
                        _ = AXIsProcessTrustedWithOptions(
                            ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
                        )
                        model.systemHUD.start()
                    }
                )
            )

            SettingsToggleRow(
                title: lang.t("settings.hud.volume"),
                isOn: Binding(get: { hud.volume }, set: { hud.volume = $0 })
            )
            .disabled(!hud.replacesSystem)

            SettingsToggleRow(
                title: lang.t("settings.hud.brightness"),
                isOn: Binding(get: { hud.brightness }, set: { hud.brightness = $0 })
            )
            .disabled(!hud.replacesSystem)

            SettingsToggleRow(
                title: lang.t("settings.hud.keyboardBacklight"),
                help: lang.t("settings.hud.keyboardBacklight.help"),
                isOn: Binding(get: { hud.keyboardBacklight }, set: { hud.keyboardBacklight = $0 })
            )
            .disabled(!hud.replacesSystem)

            SettingsToggleRow(
                title: lang.t("settings.hud.playsFeedbackSound"),
                isOn: Binding(get: { hud.playsFeedbackSound }, set: { hud.playsFeedbackSound = $0 })
            )
            .disabled(!hud.replacesSystem)

            SettingsRow(
                title: lang.t("settings.hud.limits"),
                help: lang.t("settings.hud.limits.help")
            )
        }
    }
}
