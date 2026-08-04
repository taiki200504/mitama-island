import SwiftUI

// MARK: - Usage

/// How much of each agent's allowance is left, and where that number comes from.
struct UsageSettingsPane: View {
    var model: AppModel

    @State private var confirmingUninstallBridge = false

    private var lang: LanguageManager { model.lang }

    var body: some View {
        SettingsPane(tab: .usage) {
            Section(lang.t("settings.usage.section.display")) {
                SettingsToggleRow(
                    title: lang.t("settings.usage.show"),
                    isOn: Binding(
                        get: { model.islandUsageDisplay == .compact },
                        set: { model.islandUsageDisplay = $0 ? .compact : .hidden }
                    )
                )
                SettingsToggleRow(
                    title: lang.t("settings.usage.showCodex"),
                    isOn: Binding(
                        get: { model.showCodexUsage },
                        set: { model.showCodexUsage = $0 }
                    )
                )
                SettingsRow(
                    title: lang.t("settings.usage.valueMode"),
                    availability: FeatureAvailability(.usageValueMode)
                )
                SettingsRow(
                    title: lang.t("settings.usage.thresholdAlert"),
                    availability: FeatureAvailability(.usageThresholdMonitor)
                )
                SettingsRow(
                    title: lang.t("settings.usage.resetCards"),
                    availability: FeatureAvailability(.codexResetCards)
                )
            }

            Section {
                SettingsRow(
                    title: lang.t("setup.usageBridge"),
                    help: lang.t("settings.usage.bridge.help")
                ) {
                    if model.claudeUsageInstalled {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Button(lang.t("settings.general.uninstall")) {
                                confirmingUninstallBridge = true
                            }
                        }
                    } else if model.isClaudeUsageSetupBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(lang.t("settings.general.install")) {
                            model.installClaudeUsageBridge()
                        }
                    }
                }

                if let summary = model.claudeUsageSummaryText {
                    SettingsRow(title: model.claudeUsageStatusTitle) {
                        Text(summary).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(lang.t("settings.usage.section.bridge"))
            }
            .alert(
                lang.t("settings.general.uninstallConfirmTitle"),
                isPresented: $confirmingUninstallBridge
            ) {
                Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                    model.uninstallClaudeUsageBridge()
                }
                Button(lang.t("settings.general.cancel"), role: .cancel) {}
            } message: {
                Text(lang.t("settings.general.uninstallConfirmMessage.claudeUsage"))
            }
        }
    }
}

// MARK: - SSH remote

/// Watching agents that run on another machine.
struct SSHRemoteSettingsPane: View {
    var model: AppModel

    var body: some View {
        SettingsPane(tab: .sshRemote) {
            RemoteConnectionSection(model: model)
        }
    }
}

// MARK: - Labs

/// Settings that change how the app treats the agents themselves.
struct LabsSettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }

    var body: some View {
        SettingsPane(tab: .labs) {
            Section(lang.t("settings.labs.section.updates")) {
                SettingsRow(
                    title: lang.t("settings.labs.autoUpdate"),
                    help: lang.t("settings.labs.autoUpdate.off")
                ) {
                    Text("—").foregroundStyle(.secondary)
                }
            }

            Section(lang.t("settings.labs.section.agents")) {
                SettingsRow(
                    title: lang.t("settings.labs.nativeApprovals"),
                    availability: FeatureAvailability(.approvalRouting)
                )
                SettingsRow(
                    title: lang.t("settings.labs.approvalTarget"),
                    availability: FeatureAvailability(.approvalRouting)
                )
                SettingsRow(
                    title: lang.t("settings.labs.sessionNaming"),
                    availability: FeatureAvailability(.sessionAutoNaming)
                )
            }

            Section(lang.t("settings.labs.section.stability")) {
                SettingsRow(
                    title: lang.t("settings.labs.memoryRestart"),
                    availability: FeatureAvailability(.memoryWatchdog)
                )
            }
        }
    }
}

// MARK: - mitama

/// Connection to mitama-os. Its own pane rather than a corner of the general
/// one, because this is where the agent-side integration will grow.
struct MitamaSettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }

    var body: some View {
        SettingsPane(tab: .mitama) {
            Section(lang.t("settings.mitama.section.feed")) {
                SettingsToggleRow(
                    title: lang.t("settings.general.mitamaFeed"),
                    help: mitamaFeedHelp,
                    isOn: Binding(
                        get: { model.mitamaFeedEnabled },
                        set: { model.mitamaFeedEnabled = $0 }
                    )
                )
            }

            Section(lang.t("settings.mitama.section.credentials")) {
                SettingsRow(
                    title: lang.t("settings.mitama.source"),
                    help: credentialWarning
                ) {
                    Text(credentialSourceName).foregroundStyle(.secondary)
                }
            }

            Section(lang.t("settings.mitama.section.hub")) {
                SettingsRow(title: lang.t("settings.mitama.openHub")) {
                    Button(lang.t("settings.mitama.openHub")) {
                        model.openMitamaHub()
                    }
                }
            }
        }
    }

    private var credentialSourceName: String {
        switch model.mitamaFeed.credentialSource {
        case .keychain: lang.t("settings.mitama.source.keychain")
        case .envFile:  lang.t("settings.mitama.source.envFile")
        case nil:       lang.t("settings.mitama.source.none")
        }
    }

    /// Only shown while the key is still in a file anyone can read.
    private var credentialWarning: String? {
        model.mitamaFeed.credentialSource == .envFile
            ? lang.t("settings.mitama.moveToKeychain")
            : nil
    }

    private var mitamaFeedHelp: String {
        if model.mitamaFeedEnabled, !model.mitamaFeed.isConfigured {
            return lang.t("settings.general.mitamaFeedMissingConfig")
        }
        return lang.t("settings.mitama.feed.help")
    }
}
