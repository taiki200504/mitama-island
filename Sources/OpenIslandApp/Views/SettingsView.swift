import SwiftUI
import AppKit
import OpenIslandCore

/// Removes the sidebar toggle where the API exists, and leaves the toolbar
/// alone where it does not. Hiding the whole toolbar takes the window's close,
/// minimise and zoom buttons with it.
private struct HidesSidebarToggle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbar(removing: .sidebarToggle)
        } else {
            content
        }
    }
}

// MARK: - Root settings view

struct SettingsView: View {
    var model: AppModel
    @State private var selectedTab: SettingsTab = .general

    private var lang: LanguageManager { model.lang }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 250)
        } detail: {
            detailView
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 520, idealHeight: 620)
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: .openIslandSelectSetupTab)) { _ in
            selectedTab = .integrations
        }
        .onReceive(NotificationCenter.default.publisher(for: .openIslandSelectSettingsTab)) { note in
            guard let raw = note.object as? String, let tab = SettingsTab(rawValue: raw) else { return }
            selectedTab = tab
        }
    }

    // MARK: Sidebar

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $selectedTab) {
            ForEach(SettingsSection.allCases, id: \.self) { section in
                Section {
                    ForEach(section.tabs) { tab in
                        Label {
                            Text(tab.label(lang))
                        } icon: {
                            SettingsIconChip(systemImage: tab.icon, tint: tab.tint)
                        }
                        .tag(tab)
                        // A stable handle for driving the sidebar from a UI
                        // test. Deliberately no other accessibility overrides
                        // here: the row's native selection semantics are what
                        // VoiceOver should see.
                        .accessibilityIdentifier("settings.tab.\(tab.rawValue)")
                    }
                } header: {
                    if let header = section.header(lang) {
                        Text(header)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        // Only the sidebar toggle goes. Hiding the whole window toolbar — which
        // is what this used to do — took the close, minimise and zoom buttons
        // with it and left the window unclosable by mouse.
        .modifier(HidesSidebarToggle())
    }

    // MARK: Detail

    @ViewBuilder
    private var detailView: some View {
        ZStack(alignment: .topTrailing) {
            switch selectedTab {
            case .general:
                GeneralSettingsPane(model: model)
            case .integrations:
                SetupSettingsPane(model: model)
            case .appearance:
                AppearanceSettingsPane(model: model)
            case .display:
                DisplaySettingsPane(model: model)
            case .sound:
                SoundSettingsPane(model: model)
            case .watch:
                WatchSettingsPane(model: model)
            case .about:
                AboutSettingsPane(model: model)
            case .shortcuts:
                ShortcutsSettingsPane(model: model)
            case .notifications:
                NotificationSettingsPane(model: model)
            case .usage:
                UsageSettingsPane(model: model)
            case .sshRemote:
                SSHRemoteSettingsPane(model: model)
            case .labs:
                LabsSettingsPane(model: model)
            case .mitama:
                MitamaSettingsPane(model: model)
            }

            if model.updateChecker.hasUpdate, let version = model.updateChecker.latestVersion {
                UpdateBanner(version: version, lang: lang) {
                    model.updateChecker.checkForUpdates()
                }
                .padding(.top, 8)
                .padding(.trailing, 16)
            }
        }
    }
}

// MARK: - About

struct AboutSettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }
    private let primaryInk = Color.white.opacity(0.94)

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)

                Text(lang.t("app.name"))
                    .font(.title.bold())

                Text(lang.t("app.description"))
                    .foregroundStyle(.secondary)

                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    Text(lang.t("settings.about.version", version))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider()

            Form {
                Section {
                    aboutActionRow(
                        title: lang.t("settings.about.checkForUpdates"),
                        systemImage: "arrow.triangle.2.circlepath",
                        tint: primaryInk,
                        action: {
                            model.updateChecker.checkForUpdates()
                        }
                    )
                    .disabled(!model.updateChecker.canCheckForUpdates)
                    .opacity(model.updateChecker.canCheckForUpdates ? 1 : 0.55)
                    .accessibilityIdentifier("settings.about.checkForUpdates")
                }

                // A GPL v3 fork bundling an OFL font owes both an acknowledgement.
                Section(lang.t("settings.about.credits")) {
                    LabeledContent(
                        lang.t("settings.about.credits"),
                        value: lang.t("settings.about.credits.value")
                    )
                    LabeledContent(
                        lang.t("settings.about.font"),
                        value: lang.t("settings.about.font.value")
                    )
                    Link(
                        lang.t("settings.about.source"),
                        destination: URL(string: "https://github.com/Octane0411/open-vibe-island")!
                    )
                }

                Section {
                    aboutActionRow(
                        title: lang.t("settings.about.quitApp"),
                        systemImage: "rectangle.portrait.and.arrow.right",
                        tint: Color(red: 1.0, green: 0.29, blue: 0.29),
                        action: {
                            model.quitApplication()
                        }
                    )
                    .accessibilityIdentifier("settings.about.quitApp")
                }
            }
            .formStyle(.grouped)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .navigationTitle(lang.t("settings.tab.about"))
    }

    private func aboutActionRow(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18, alignment: .leading)

                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))

                Spacer()
            }
            .foregroundStyle(tint)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Setup

struct SetupSettingsPane: View {
    var model: AppModel

    @State private var confirmingUninstallClaude = false
    @State private var confirmingUninstallCodex = false
    @State private var confirmingUninstallOpenCode = false
    @State private var confirmingUninstallQoder = false
    @State private var confirmingUninstallQwenCode = false
    @State private var confirmingUninstallFactory = false
    @State private var confirmingUninstallCodebuddy = false
    @State private var confirmingUninstallCursor = false
    @State private var confirmingUninstallGemini = false
    @State private var confirmingUninstallKimi = false
    @State private var confirmingUninstallClaudeUsage = false

    private var lang: LanguageManager { model.lang }

    var body: some View {
        Form {
            if !model.hasAnyInstalledAgent {
                emptyStateBanner
            }

            if !model.sessionsPredatingHookInstall.isEmpty {
                restartSessionsBanner
            }

            claudeConfigDirectorySection

            Section(lang.t("setup.section.hooks")) {
                hookRow(
                    name: "Claude Code",
                    installed: model.claudeHooksInstalled,
                    busy: model.isClaudeHookSetupBusy,
                    configLocationURL: model.claudeHookStatus?.settingsURL,
                    installAction: { model.installClaudeHooks() },
                    uninstallAction: { confirmingUninstallClaude = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallClaude) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallClaudeHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text(lang.t("settings.general.uninstallConfirmMessage.claude"))
                }

                hookRow(
                    name: "Codex",
                    installed: model.codexHooksInstalled,
                    busy: model.isCodexSetupBusy,
                    configLocationURL: codexHookConfigURL,
                    installAction: { model.installCodexHooks() },
                    uninstallAction: { confirmingUninstallCodex = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallCodex) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallCodexHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text(lang.t("settings.general.uninstallConfirmMessage.codex"))
                }

                hookRow(
                    name: "OpenCode",
                    installed: model.openCodePluginInstalled,
                    busy: model.isOpenCodeSetupBusy,
                    requiresBinary: false,
                    configLocationURL: model.openCodePluginStatus?.configURL,
                    installAction: { model.installOpenCodePlugin() },
                    uninstallAction: { confirmingUninstallOpenCode = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallOpenCode) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallOpenCodePlugin()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text(lang.t("setup.uninstallHooksMessage", "~/.config/opencode/plugins/"))
                }

                hookRow(
                    name: "Qoder",
                    installed: model.qoderHooksInstalled,
                    busy: model.isQoderHookSetupBusy,
                    configLocationURL: model.qoderHookStatus?.settingsURL,
                    installAction: { model.installQoderHooks() },
                    uninstallAction: { confirmingUninstallQoder = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallQoder) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallQoderHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text(lang.t("setup.uninstallHooksMessage", "~/.qoder/settings.json"))
                }

                hookRow(
                    name: "Qwen Code",
                    installed: model.qwenCodeHooksInstalled,
                    busy: model.isQwenCodeHookSetupBusy,
                    configLocationURL: model.qwenCodeHookStatus?.settingsURL,
                    installAction: { model.installQwenCodeHooks() },
                    uninstallAction: { confirmingUninstallQwenCode = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallQwenCode) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallQwenCodeHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text(lang.t("setup.uninstallHooksMessage", "~/.qwen/settings.json"))
                }

                hookRow(
                    name: "Factory",
                    installed: model.factoryHooksInstalled,
                    busy: model.isFactoryHookSetupBusy,
                    configLocationURL: model.factoryHookStatus?.settingsURL,
                    installAction: { model.installFactoryHooks() },
                    uninstallAction: { confirmingUninstallFactory = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallFactory) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallFactoryHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text(lang.t("setup.uninstallHooksMessage", "~/.factory/settings.json"))
                }

                hookRow(
                    name: "CodeBuddy",
                    installed: model.codebuddyHooksInstalled,
                    busy: model.isCodebuddyHookSetupBusy,
                    configLocationURL: model.codebuddyHookStatus?.settingsURL,
                    installAction: { model.installCodebuddyHooks() },
                    uninstallAction: { confirmingUninstallCodebuddy = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallCodebuddy) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallCodebuddyHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text(lang.t("setup.uninstallHooksMessage", "~/.codebuddy/settings.json"))
                }

                hookRow(
                    name: "Cursor",
                    installed: model.cursorHooksInstalled,
                    busy: model.isCursorHookSetupBusy,
                    requiresBinary: true,
                    configLocationURL: model.cursorHookStatus?.hooksURL,
                    installAction: { model.installCursorHooks() },
                    uninstallAction: { confirmingUninstallCursor = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallCursor) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallCursorHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text(lang.t("setup.uninstallHooksMessage", "~/.cursor/hooks.json"))
                }

                hookRow(
                    name: "Gemini CLI",
                    installed: model.geminiHooksInstalled,
                    busy: model.isGeminiHookSetupBusy,
                    configLocationURL: geminiHookConfigURL,
                    installAction: { model.installGeminiHooks() },
                    uninstallAction: { confirmingUninstallGemini = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallGemini) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallGeminiHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text(lang.t("setup.uninstallHooksMessage", "~/.gemini/settings.json"))
                }

                hookRow(
                    name: "Kimi CLI",
                    installed: model.kimiHooksInstalled,
                    busy: model.isKimiHookSetupBusy,
                    configLocationURL: model.kimiHookStatus?.configURL,
                    installAction: { model.installKimiHooks() },
                    uninstallAction: { confirmingUninstallKimi = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallKimi) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallKimiHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text(lang.t("setup.uninstallHooksMessage", "~/.kimi/config.toml"))
                }
            }

            Section {
                HStack {
                    Label(lang.t("setup.usageBridge"), systemImage: "chart.bar")
                    Spacer()
                    if model.claudeUsageInstalled {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(lang.t("setup.usageBridgeReady"))
                                .foregroundStyle(.secondary)
                        }
                        Button(lang.t("settings.general.uninstall")) {
                            confirmingUninstallClaudeUsage = true
                        }
                    } else if model.isClaudeUsageSetupBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(lang.t("settings.general.install")) {
                            model.installClaudeUsageBridge()
                        }
                    }
                }
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallClaudeUsage) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallClaudeUsageBridge()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text(lang.t("settings.general.uninstallConfirmMessage.claudeUsage"))
                }

                Toggle(lang.t("settings.general.showCodexUsage"), isOn: Binding(
                    get: { model.showCodexUsage },
                    set: { model.showCodexUsage = $0 }
                ))
            } header: {
                HStack(spacing: 4) {
                    Text(lang.t("setup.section.usage"))
                    Text(lang.t("setup.optional"))
                        .foregroundStyle(.tertiary)
                }
            }

            Section(lang.t("setup.section.permissions")) {
                HStack(alignment: .top) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lang.t("setup.permissionsTitle"))
                            Text(lang.t("setup.permissionsDesc"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "lock.shield")
                    }
                    Spacer()
                }
            }

            hookDiagnosticsSection

            RemoteConnectionSection(model: model)

            Section {
                Button(lang.t("setup.installAll")) {
                    if !model.claudeHooksInstalled { model.installClaudeHooks() }
                    if !model.codexHooksInstalled { model.installCodexHooks() }
                    if !model.openCodePluginInstalled { model.installOpenCodePlugin() }
                    if !model.qoderHooksInstalled { model.installQoderHooks() }
                    if !model.qwenCodeHooksInstalled { model.installQwenCodeHooks() }
                    if !model.factoryHooksInstalled { model.installFactoryHooks() }
                    if !model.codebuddyHooksInstalled { model.installCodebuddyHooks() }
                    if !model.cursorHooksInstalled { model.installCursorHooks() }
                    if !model.geminiHooksInstalled { model.installGeminiHooks() }
                    if !model.kimiHooksInstalled { model.installKimiHooks() }
                    if !model.claudeUsageInstalled { model.installClaudeUsageBridge() }
                }
                .disabled(model.hooksBinaryURL == nil || allReady)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.integrations"))
    }

    @ViewBuilder
    private var claudeConfigDirectorySection: some View {
        Section {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lang.t("setup.claudeConfigDir.title"))
                        Text(ClaudeConfigDirectory.resolved().path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } icon: {
                    Image(systemName: "folder")
                }
                Spacer()
                if ClaudeConfigDirectory.customDirectory != nil {
                    Button(lang.t("setup.claudeConfigDir.reset")) {
                        model.updateClaudeConfigDirectory(to: nil)
                    }
                    .font(.caption)
                }
                Button(lang.t("setup.claudeConfigDir.choose")) {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.canCreateDirectories = true
                    panel.showsHiddenFiles = true
                    panel.prompt = lang.t("setup.claudeConfigDir.choose")
                    if panel.runModal() == .OK, let url = panel.url {
                        model.updateClaudeConfigDirectory(to: url)
                    }
                }
            }
        } header: {
            HStack(spacing: 4) {
                Text(lang.t("setup.claudeConfigDir.section"))
                Text(lang.t("setup.optional"))
                    .foregroundStyle(.tertiary)
            }
        } footer: {
            Text(lang.t("setup.claudeConfigDir.footer"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var allReady: Bool {
        model.claudeHooksInstalled && model.codexHooksInstalled && model.openCodePluginInstalled
            && model.qoderHooksInstalled && model.qwenCodeHooksInstalled && model.factoryHooksInstalled && model.codebuddyHooksInstalled
            && model.cursorHooksInstalled && model.geminiHooksInstalled && model.kimiHooksInstalled && model.claudeUsageInstalled
    }

    /// Points out sessions that were already running when hooks were installed.
    ///
    /// Not dismissible on purpose, and it needs no dismiss button: it is derived
    /// from the sessions themselves, so restarting the last one makes it go away
    /// and no stale "you have unread advice" state can linger.
    @ViewBuilder
    private var restartSessionsBanner: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(lang.t("setup.banner.restartSessions.title"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(
                        lang.t("setup.banner.restartSessions.message")
                            .replacingOccurrences(
                                of: "{names}",
                                with: model.sessionsPredatingHookInstall
                                    .prefix(3)
                                    .map(\.title)
                                    .joined(separator: ", ")
                            )
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var emptyStateBanner: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(lang.t("setup.banner.noHooks.title"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(lang.t("setup.banner.noHooks.message"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    private var codexHookConfigURL: URL? {
        if let hooksURL = model.codexHookStatus?.hooksURL, FileManager.default.fileExists(atPath: hooksURL.path) {
            return hooksURL
        }
        return model.codexHookStatus?.configURL ?? model.codexHookStatus?.hooksURL
    }

    private var geminiHookConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/settings.json")
    }

    private var hasErrors: Bool {
        let claudeErrors = model.claudeHealthReport?.errors.count ?? 0
        let codexErrors = model.codexHealthReport?.errors.count ?? 0
        return claudeErrors + codexErrors > 0
    }

    private var hasRepairableIssues: Bool {
        let claude = model.claudeHealthReport?.repairableIssues.isEmpty == false
        let codex = model.codexHealthReport?.repairableIssues.isEmpty == false
        return claude || codex
    }

    private var hasNotices: Bool {
        let claude = model.claudeHealthReport?.notices.isEmpty == false
        let codex = model.codexHealthReport?.notices.isEmpty == false
        return claude || codex
    }

    @ViewBuilder
    private var hookDiagnosticsSection: some View {
        Section {
            if let claudeReport = model.claudeHealthReport, !claudeReport.issues.isEmpty {
                issueList(report: claudeReport)
            }
            if let codexReport = model.codexHealthReport, !codexReport.issues.isEmpty {
                issueList(report: codexReport)
            }

            if model.claudeHealthReport == nil && model.codexHealthReport == nil {
                HStack {
                    Text(lang.t("setup.diagnostics.notRun"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(lang.t("setup.diagnostics.runCheck")) {
                        model.runHealthChecks()
                    }
                }
            } else if !hasErrors {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(lang.t("setup.diagnostics.allHealthy"))
                    Spacer()
                    Button(lang.t("setup.diagnostics.recheck")) {
                        model.runHealthChecks()
                    }
                    .font(.caption)
                }
            } else {
                HStack(spacing: 10) {
                    Button(lang.t("setup.diagnostics.recheck")) {
                        model.runHealthChecks()
                    }

                    if hasRepairableIssues {
                        Button(lang.t("setup.diagnostics.repair")) {
                            model.repairHooks()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        } header: {
            HStack(spacing: 4) {
                Text(lang.t("setup.section.diagnostics"))
                if hasErrors {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption2)
                }
            }
        }
    }

    @ViewBuilder
    private func issueList(report: HookHealthReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(report.agent == "claude" ? "Claude Code" : "Codex")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            ForEach(Array(report.issues.enumerated()), id: \.offset) { _, issue in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: issueIcon(for: issue))
                        .font(.caption2)
                        .foregroundStyle(issueColor(for: issue))
                        .frame(width: 14)

                    Text(issue.description)
                        .font(.caption)
                        .foregroundStyle(issue.severity == .info ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let binaryPath = report.binaryPath {
                Text(lang.t("setup.binaryPath", binaryPath))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func issueIcon(for issue: HookHealthReport.Issue) -> String {
        switch issue.severity {
        case .info: "info.circle.fill"
        case .error: issue.isAutoRepairable ? "wrench.fill" : "exclamationmark.triangle.fill"
        }
    }

    private func issueColor(for issue: HookHealthReport.Issue) -> Color {
        switch issue.severity {
        case .info: .blue
        case .error: issue.isAutoRepairable ? .orange : .red
        }
    }

    @ViewBuilder
    private func hookRow(
        name: String,
        installed: Bool,
        busy: Bool,
        requiresBinary: Bool = true,
        configLocationURL: URL? = nil,
        installAction: @escaping () -> Void,
        uninstallAction: @escaping () -> Void
    ) -> some View {
        HStack {
            Label(name, systemImage: "terminal")
            Spacer()
            if installed {
                HStack(spacing: 8) {
                    if let configLocationURL {
                        Button {
                            revealInFinder(configLocationURL)
                        } label: {
                            Image(systemName: "arrow.up.forward.square")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(lang.t("setup.revealConfigLocation"))
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(lang.t("settings.general.activated"))
                            .foregroundStyle(.secondary)
                    }
                    Button(lang.t("settings.general.uninstall")) {
                        uninstallAction()
                    }
                    .foregroundStyle(.red)
                    .font(.caption)
                }
            } else if busy {
                ProgressView().controlSize(.small)
            } else {
                Button(lang.t("settings.general.install")) {
                    installAction()
                }
                .disabled(requiresBinary && model.hooksBinaryURL == nil)
            }
        }
    }

    private func revealInFinder(_ url: URL) {
        let fileManager = FileManager.default
        let standardizedURL = url.standardizedFileURL

        if fileManager.fileExists(atPath: standardizedURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([standardizedURL])
            return
        }

        let directoryURL = standardizedURL.deletingLastPathComponent()
        if fileManager.fileExists(atPath: directoryURL.path) {
            NSWorkspace.shared.open(directoryURL)
        }
    }
}

// MARK: - Watch

struct WatchSettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }

    @State private var pairingCode: String = "----"

    var body: some View {
        Form {
            Section {
                Toggle(lang.t("settings.watch.notifications"), isOn: Binding(
                    get: { model.watchNotificationEnabled },
                    set: { model.watchNotificationEnabled = $0 }
                ))

                if model.watchNotificationEnabled {
                    Text(lang.t("settings.watch.notifications.help"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(lang.t("settings.section.general"))
            }

            if model.watchNotificationEnabled {
                Section("Pairing") {
                    HStack {
                        Text("Pairing Code")
                        Spacer()
                        Text(pairingCode)
                            .font(.islandMono(size: 24, weight: .bold))
                            .foregroundStyle(.blue)
                    }

                    Text("Enter this code on your iPhone app to pair. Code expires after 2 minutes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Refresh Code") {
                        model.watchRelay?.endpoint.regeneratePairingCode()
                        pairingCode = model.watchPairingCode
                    }
                }

                Section("Paired Devices") {
                    if model.watchConnectedDevices > 0 {
                        HStack {
                            Label("iPhone", systemImage: "iphone")
                            Spacer()
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 7, height: 7)
                                Text("Connected")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        HStack {
                            Label("No devices paired", systemImage: "iphone.slash")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("Revoke All Pairings", role: .destructive) {
                        model.watchRelay?.endpoint.revokeAllTokens()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Watch")
        .onAppear {
            pairingCode = model.watchPairingCode
        }
    }
}

// MARK: - Placeholder

struct PlaceholderSettingsPane: View {
    var model: AppModel
    let titleKey: String
    let subtitleKey: String

    private var lang: LanguageManager { model.lang }

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(lang.t(subtitleKey))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .navigationTitle(lang.t(titleKey))
    }
}

// MARK: - Remote Connection

struct RemoteConnectionSection: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }

    @State private var copiedCommand: String?

    private var remoteSessionCount: Int {
        model.state.sessions.filter(\.isRemote).count
    }

    private var socketName: String {
        "open-island-\(getuid()).sock"
    }

    private var setupCommand: String {
        "./scripts/remote-setup.sh user@host"
    }

    private var sshCommand: String {
        "ssh -R /tmp/\(socketName):/tmp/\(socketName) user@host"
    }

    private var sshConfigSnippet: String {
        """
        Host myserver
            RemoteForward /tmp/\(socketName) /tmp/\(socketName)
        """
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                // Status
                HStack {
                    Label(lang.t("settings.sshRemote.title"), systemImage: "network")
                    Spacer()
                    if remoteSessionCount > 0 {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.green)
                                .frame(width: 7, height: 7)
                            Text(lang.t("settings.sshRemote.activeCount", String(remoteSessionCount)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(lang.t("settings.sshRemote.none"))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(lang.t("settings.sshRemote.intro"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Step 1
                remoteSetupStep(
                    number: "1",
                    title: lang.t("settings.sshRemote.step1"),
                    description: "Run from the Open Island repo directory:",
                    command: setupCommand
                )

                // Step 2
                remoteSetupStep(
                    number: "2",
                    title: lang.t("settings.sshRemote.step2"),
                    description: "Add to ~/.ssh/config (recommended):",
                    command: sshConfigSnippet,
                    multiline: true
                )

                // Step 2 alternative
                VStack(alignment: .leading, spacing: 4) {
                    Text(lang.t("settings.sshRemote.direct"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                    copyableCommand(sshCommand)
                }

                // Tip
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.blue.opacity(0.8))
                        .padding(.top, 1)
                    Text(lang.t("settings.sshRemote.note"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            HStack(spacing: 4) {
                Text(lang.t("settings.sshRemote.title"))
                Text("Beta")
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func remoteSetupStep(
        number: String,
        title: String,
        description: String,
        command: String,
        multiline: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(number)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(.blue.opacity(0.7)))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            Text(description)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            copyableCommand(command, multiline: multiline)
        }
    }

    @ViewBuilder
    private func copyableCommand(_ command: String, multiline: Bool = false) -> some View {
        let isCopied = copiedCommand == command
        GroupBox {
            HStack(alignment: multiline ? .top : .center) {
                Text(command)
                    .font(.islandMono(size: 10.5))
                    .foregroundStyle(.primary)
                    .lineLimit(multiline ? nil : 1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copiedCommand = command
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if copiedCommand == command {
                            copiedCommand = nil
                        }
                    }
                } label: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(isCopied ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, multiline ? 2 : 0)
        }
    }
}

// MARK: - Update Banner

struct UpdateBanner: View {
    let version: String
    let lang: LanguageManager
    var onUpdate: () -> Void

    var body: some View {
        Button(action: onUpdate) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text(lang.t("settings.update.available", version))
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.blue)
            )
        }
        .buttonStyle(.plain)
        .shadow(color: .blue.opacity(0.3), radius: 4, y: 2)
    }
}
