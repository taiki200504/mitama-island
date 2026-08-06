import AppKit
import Foundation
import Observation
import OpenIslandCore
import SwiftUI

extension Notification.Name {
    /// Posted by `AppModel.showOnboarding()` to ask `SettingsView` to
    /// switch to the Setup tab. Lets the empty-state CTAs deliver the
    /// user to the right place without `SettingsView`'s `@State` having
    /// to leak into `AppModel`.
    static let openIslandSelectSetupTab = Notification.Name("openIslandSelectSetupTab")

    /// Carries the tab's raw value in `object`. Used by the harness to walk
    /// every pane, and by anything else that needs to land on a specific one.
    static let openIslandSelectSettingsTab = Notification.Name("openIslandSelectSettingsTab")
}

@MainActor
@Observable
final class AppModel {
    private static let soundMutedDefaultsKey = "overlay.sound.muted"
    private static let showDockIconDefaultsKey = "app.showDockIcon"
    private static let hapticFeedbackEnabledDefaultsKey = "app.hapticFeedbackEnabled"
    private static let islandRightSlotDefaultsKey = "appearance.island.v6.rightSlot"
    private static let islandCenterLabelDefaultsKey = "appearance.island.v6.centerLabel"
    private static let showCodexUsageDefaultsKey = "app.showCodexUsage"
    private static let completionReplyEnabledDefaultsKey = "feature.completionReply.enabled"
    /// Set once, the first time an installed copy runs, so the login-item
    /// registration below never fights a user who turned it back off.
    private static let launchAtLoginPromptedDefaultsKey = "launchAtLogin.autoRegistered"
    /// How long a session restored from the registry stays on the list before
    /// process discovery has confirmed it is still alive.
    private static let restoredSessionVisibilityWindow: TimeInterval = 30 * 60
    private static let legacyIslandSessionStateIndicatorDefaultsKey = "appearance.island.v8.stateIndicator"
    private static let legacyIslandSessionGroupDefaultsKey = "appearance.island.v8.sessionGroup"
    private static let legacyIslandSessionSortDefaultsKey = "appearance.island.v8.sessionSort"
    private static let legacyCompletedStaleThresholdDefaultsKey = "appearance.island.v8.completedStaleThreshold"
    private static let appearanceProfileSettingsDefaultsKey = "appearance.island.v8.settingsProfile"

    private static let syntheticClaudeSessionPrefix = "claude-process:"
    private static let liveSessionStalenessWindow: TimeInterval = 15 * 60
    private static let jumpOverlayDismissLeadTime: Duration = .milliseconds(20)
    private static let agentsGridObservedSequenceLimit = 512
    /// Fallback used before any window exists; the live value comes from
    /// `settings.behaviour.hoverDuration`.
    static let hoverOpenDelay: TimeInterval = BehaviourSettings.Defaults.hoverDuration

    struct AcceptanceStep: Identifiable {
        let id: String
        let title: String
        let detail: String
        let isComplete: Bool
    }

    let lang = LanguageManager.shared
    let settings: SettingsStore

    /// Focus, screen lock and screen sharing — the moments the user asked us to
    /// hold the panel back.
    let quietScenes: QuietSceneMonitor

    var state = SessionState() {
        didSet {
            _cachedSessionBuckets = nil
            pruneAgentsGridObservationTicketsIfNeeded()
            bridgeServer.updateStateSnapshot(state)
        }
    }
    @ObservationIgnored private var _cachedSessionBuckets: (primary: [AgentSession], restored: [AgentSession], overflow: [AgentSession])?

    /// Monotonic ticket assigned the first time a session ID shows up in the
    /// closed-island's right-slot surfaced set. Drives the grid's display
    /// order: newly-surfaced sessions always land at the end, and a session
    /// that briefly leaves (e.g. attachment flip) keeps its old slot when it
    /// returns. Persists for the process lifetime; session IDs are UUIDs so
    /// accumulation over time is bounded in practice.
    @ObservationIgnored private var _agentsGridObservedSequence: [String: Int] = [:]
    @ObservationIgnored private var _agentsGridNextTicket: Int = 0
    var selectedSessionID: String?
    let hooks = HookInstallationCoordinator()
    let overlay: OverlayUICoordinator
    let discovery = SessionDiscoveryCoordinator()
    let monitoring = ProcessMonitoringCoordinator()
    let codexAppServer = CodexAppServerCoordinator()
    let updateChecker = UpdateChecker()

    var notchStatus: NotchStatus {
        get { overlay.notchStatus }
        set { overlay.notchStatus = newValue }
    }
    var notchOpenReason: NotchOpenReason? {
        get { overlay.notchOpenReason }
        set { overlay.notchOpenReason = newValue }
    }
    var islandSurface: IslandSurface {
        get { overlay.islandSurface }
        set { overlay.islandSurface = newValue }
    }
    var isOverlayVisible: Bool { overlay.isOverlayVisible }
    var isOverlayCloseTransitionPending: Bool { overlay.isCloseTransitionPending }
    var isCodexSetupBusy: Bool { hooks.isCodexSetupBusy }
    var isClaudeHookSetupBusy: Bool { hooks.isClaudeHookSetupBusy }
    var isClaudeUsageSetupBusy: Bool { hooks.isClaudeUsageSetupBusy }
    var codexHookStatus: CodexHookInstallationStatus? { hooks.codexHookStatus }
    var claudeHookStatus: ClaudeHookInstallationStatus? { hooks.claudeHookStatus }
    var claudeStatusLineStatus: ClaudeStatusLineInstallationStatus? { hooks.claudeStatusLineStatus }
    var claudeUsageSnapshot: ClaudeUsageSnapshot? { hooks.claudeUsageSnapshot }
    var codexUsageSnapshot: CodexUsageSnapshot? { hooks.codexUsageSnapshot }
    var hooksBinaryURL: URL? { hooks.hooksBinaryURL }
    var codexHooksInstalled: Bool { hooks.codexHooksInstalled }
    var claudeHooksInstalled: Bool { hooks.claudeHooksInstalled }
    var qoderHooksInstalled: Bool { hooks.qoderHooksInstalled }
    var qwenCodeHooksInstalled: Bool { hooks.qwenCodeHooksInstalled }
    var factoryHooksInstalled: Bool { hooks.factoryHooksInstalled }
    var codebuddyHooksInstalled: Bool { hooks.codebuddyHooksInstalled }
    var qoderHookStatus: ClaudeHookInstallationStatus? { hooks.qoderHookStatus }
    var qwenCodeHookStatus: ClaudeHookInstallationStatus? { hooks.qwenCodeHookStatus }
    var factoryHookStatus: ClaudeHookInstallationStatus? { hooks.factoryHookStatus }
    var codebuddyHookStatus: ClaudeHookInstallationStatus? { hooks.codebuddyHookStatus }
    var isQoderHookSetupBusy: Bool { hooks.isQoderHookSetupBusy }
    var isQwenCodeHookSetupBusy: Bool { hooks.isQwenCodeHookSetupBusy }
    var isFactoryHookSetupBusy: Bool { hooks.isFactoryHookSetupBusy }
    var isCodebuddyHookSetupBusy: Bool { hooks.isCodebuddyHookSetupBusy }
    var openCodePluginInstalled: Bool { hooks.openCodePluginInstalled }
    var claudeUsageInstalled: Bool { hooks.claudeUsageInstalled }
    var claudeHookStatusTitle: String { hooks.claudeHookStatusTitle }
    var claudeHookStatusSummary: String { hooks.claudeHookStatusSummary }
    var claudeUsageStatusTitle: String { hooks.claudeUsageStatusTitle }
    var claudeUsageStatusSummary: String { hooks.claudeUsageStatusSummary }
    var claudeUsageSummaryText: String? { hooks.claudeUsageSummaryText }
    var codexUsageStatusTitle: String { hooks.codexUsageStatusTitle }
    var codexUsageStatusSummary: String { hooks.codexUsageStatusSummary }
    var codexUsageSummaryText: String? { hooks.codexUsageSummaryText }
    var openCodePluginStatus: OpenCodePluginInstallationStatus? { hooks.openCodePluginStatus }
    var isOpenCodeSetupBusy: Bool { hooks.isOpenCodeSetupBusy }
    var openCodePluginStatusTitle: String { hooks.openCodePluginStatusTitle }
    var openCodePluginStatusSummary: String { hooks.openCodePluginStatusSummary }
    var claudeHealthReport: HookHealthReport? { hooks.claudeHealthReport }
    var codexHealthReport: HookHealthReport? { hooks.codexHealthReport }
    var cursorHooksInstalled: Bool { hooks.cursorHooksInstalled }
    var isCursorHookSetupBusy: Bool { hooks.isCursorHookSetupBusy }
    var cursorHookStatus: CursorHookInstallationStatus? { hooks.cursorHookStatus }
    var cursorHookStatusTitle: String { hooks.cursorHookStatusTitle }
    var cursorHookStatusSummary: String { hooks.cursorHookStatusSummary }
    var geminiHooksInstalled: Bool { hooks.geminiHooksInstalled }
    var isGeminiHookSetupBusy: Bool { hooks.isGeminiHookSetupBusy }
    var geminiHookStatus: GeminiHookInstallationStatus? { hooks.geminiHookStatus }
    var geminiHookStatusTitle: String { hooks.geminiHookStatusTitle }
    var geminiHookStatusSummary: String { hooks.geminiHookStatusSummary }
    var kimiHooksInstalled: Bool { hooks.kimiHooksInstalled }
    var isKimiHookSetupBusy: Bool { hooks.isKimiHookSetupBusy }
    var kimiHookStatus: KimiHookInstallationStatus? { hooks.kimiHookStatus }
    var kimiHookStatusTitle: String { hooks.kimiHookStatusTitle }
    var kimiHookStatusSummary: String { hooks.kimiHookStatusSummary }
    var codexHookStatusTitle: String { hooks.codexHookStatusTitle }
    var codexHookStatusSummary: String { hooks.codexHookStatusSummary }

    /// Mirrors `AgentIntentStore.firstLaunchCompleted`. Onboarding sets this
    /// to true after the user completes (or explicitly skips) the flow;
    /// legacy migration also flips it for users upgrading with existing
    /// hooks.
    var firstLaunchCompleted: Bool {
        get { hooks.intentStore.firstLaunchCompleted }
        set { hooks.intentStore.firstLaunchCompleted = newValue }
    }

    /// True if at least one managed hook is currently present on disk.
    /// Drives the "configure agents" empty-state prompts in the island and
    /// the settings window.
    var hasAnyInstalledAgent: Bool {
        hooks.claudeHooksInstalled
            || hooks.codexHooksInstalled
            || hooks.cursorHooksInstalled
            || hooks.qoderHooksInstalled
            || hooks.qwenCodeHooksInstalled
            || hooks.factoryHooksInstalled
            || hooks.codebuddyHooksInstalled
            || hooks.openCodePluginInstalled
            || hooks.geminiHooksInstalled
            || hooks.kimiHooksInstalled
    }
    func refreshCodexHookStatus() { hooks.refreshCodexHookStatus() }
    func refreshClaudeHookStatus() { hooks.refreshClaudeHookStatus() }
    func refreshOpenCodePluginStatus() { hooks.refreshOpenCodePluginStatus() }
    func refreshCursorHookStatus() { hooks.refreshCursorHookStatus() }
    func refreshClaudeUsageState() { hooks.refreshClaudeUsageState() }
    func refreshCodexUsageState() { hooks.refreshCodexUsageState() }
    func installCodexHooks() { hooks.installCodexHooks() }
    func uninstallCodexHooks() { hooks.uninstallCodexHooks() }
    func installClaudeHooks() { hooks.installClaudeHooks() }
    func uninstallClaudeHooks() { hooks.uninstallClaudeHooks() }
    func installQoderHooks() { hooks.installQoderHooks() }
    func uninstallQoderHooks() { hooks.uninstallQoderHooks() }
    func installQwenCodeHooks() { hooks.installQwenCodeHooks() }
    func uninstallQwenCodeHooks() { hooks.uninstallQwenCodeHooks() }
    func installFactoryHooks() { hooks.installFactoryHooks() }
    func uninstallFactoryHooks() { hooks.uninstallFactoryHooks() }
    func installCodebuddyHooks() { hooks.installCodebuddyHooks() }
    func uninstallCodebuddyHooks() { hooks.uninstallCodebuddyHooks() }
    func refreshCCForkHookStatuses() { hooks.refreshCCForkHookStatuses() }
    func installOpenCodePlugin() { hooks.installOpenCodePlugin() }
    func uninstallOpenCodePlugin() { hooks.uninstallOpenCodePlugin() }
    func installCursorHooks() { hooks.installCursorHooks() }
    func uninstallCursorHooks() { hooks.uninstallCursorHooks() }
    func refreshGeminiHookStatus() { hooks.refreshGeminiHookStatus() }
    func installGeminiHooks() { hooks.installGeminiHooks() }
    func uninstallGeminiHooks() { hooks.uninstallGeminiHooks() }
    func refreshKimiHookStatus() { hooks.refreshKimiHookStatus() }
    func installKimiHooks() { hooks.installKimiHooks() }
    func uninstallKimiHooks() { hooks.uninstallKimiHooks() }
    func installClaudeUsageBridge() { hooks.installClaudeUsageBridge() }
    func uninstallClaudeUsageBridge() { hooks.uninstallClaudeUsageBridge() }
    func updateClaudeConfigDirectory(to newDirectory: URL?) { hooks.updateClaudeConfigDirectory(to: newDirectory) }
    func runHealthChecks() { hooks.runHealthChecks() }
    func repairHooks() {
        Task { @MainActor in
            await hooks.repairHooksIfNeeded()
        }
    }
    var isBridgeReady = false
    var lastActionMessage = "Waiting for agent hook events..." {
        didSet {
            guard lastActionMessage != oldValue else {
                return
            }

            harnessRuntimeMonitor?.recordLog(lastActionMessage)
        }
    }
    var isResolvingInitialLiveSessions: Bool {
        get { monitoring.isResolvingInitialLiveSessions }
        set {
            guard monitoring.isResolvingInitialLiveSessions != newValue else {
                return
            }
            monitoring.isResolvingInitialLiveSessions = newValue
            // Session visibility depends on this flag while the first process
            // reconcile is still running, so the bucket cache computed under
            // the old value is stale the moment it flips.
            _cachedSessionBuckets = nil
        }
    }
    var overlayDisplayOptions: [OverlayDisplayOption] {
        get { overlay.overlayDisplayOptions }
        set { overlay.overlayDisplayOptions = newValue }
    }
    var overlayPlacementDiagnostics: OverlayPlacementDiagnostics? {
        get { overlay.overlayPlacementDiagnostics }
        set { overlay.overlayPlacementDiagnostics = newValue }
    }
    var showDockIcon: Bool = false {
        didSet {
            guard hasFinishedInit, showDockIcon != oldValue else { return }
            UserDefaults.standard.set(showDockIcon, forKey: Self.showDockIconDefaultsKey)
            NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
            if !showDockIcon {
                // macOS does not immediately refresh the Dock when switching to
                // .accessory at runtime. Briefly activating another app forces
                // the Dock to drop the icon.
                NSApp.hide(nil)
                DispatchQueue.main.async {
                    NSApp.unhide(nil)
                }
            }
        }
    }
    var hapticFeedbackEnabled: Bool = false {
        didSet {
            guard hasFinishedInit, hapticFeedbackEnabled != oldValue else { return }
            UserDefaults.standard.set(hapticFeedbackEnabled, forKey: Self.hapticFeedbackEnabledDefaultsKey)
        }
    }
    var showCodexUsage: Bool = false {
        didSet {
            guard hasFinishedInit, showCodexUsage != oldValue else { return }
            UserDefaults.standard.set(showCodexUsage, forKey: Self.showCodexUsageDefaultsKey)
        }
    }
    var completionReplyEnabled: Bool = false {
        didSet {
            guard hasFinishedInit, completionReplyEnabled != oldValue else { return }
            UserDefaults.standard.set(completionReplyEnabled, forKey: Self.completionReplyEnabledDefaultsKey)
            refreshOverlayPlacementIfVisible()
        }
    }
    /// Kept as a name the notification path already reads; the value lives in
    /// `settings.behaviour.smartSuppression`, which the general pane edits.
    var suppressFrontmostNotifications: Bool {
        get { settings.behaviour.smartSuppression }
        set { settings.behaviour.smartSuppression = newValue }
    }

    var launchAtLoginEnabled: Bool = false {
        didSet {
            guard !isApplyingLaunchAtLogin, hasFinishedInit, launchAtLoginEnabled != oldValue else { return }
            do {
                try LaunchAtLoginService.shared.setEnabled(launchAtLoginEnabled)
            } catch {
                isApplyingLaunchAtLogin = true
                launchAtLoginEnabled = oldValue
                isApplyingLaunchAtLogin = false
                presentLaunchAtLoginError(error)
            }
        }
    }
    private func presentLaunchAtLoginError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = lang.t("settings.general.launchAtLogin")
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
    @ObservationIgnored
    private var isApplyingLaunchAtLogin = false
    /// Backed by `settings.sound` so the island's speaker button and the sound
    /// pane are the same switch rather than two that happen to agree.
    var isSoundMuted: Bool {
        get { settings.sound.isMuted }
        set {
            guard newValue != settings.sound.isMuted else { return }
            settings.sound.isMuted = newValue
            lastActionMessage = newValue
                ? "Island sound notifications muted."
                : "Island sound notifications enabled."
        }
    }
    var selectedSoundName: String = NotificationSoundService.defaultSoundName {
        didSet {
            guard selectedSoundName != oldValue else { return }
            NotificationSoundService.selectedSoundName = selectedSoundName
        }
    }
    var overlayDisplaySelectionID: String {
        get { overlay.overlayDisplaySelectionID }
        set { overlay.overlayDisplaySelectionID = newValue }
    }

    // MARK: - Appearance

    var appearanceSettingsProfile: IslandAppearanceDisplayProfile = .topBar {
        didSet {
            guard appearanceSettingsProfile != oldValue else { return }
            UserDefaults.standard.set(appearanceSettingsProfile.rawValue, forKey: Self.appearanceProfileSettingsDefaultsKey)
        }
    }

    private var notchAppearancePreferences = IslandAppearancePreferences() {
        didSet {
            guard notchAppearancePreferences != oldValue else { return }
            persistAppearancePreferences(notchAppearancePreferences, for: .notch)
            if activeAppearanceProfile == .notch { appearancePreferencesDidChange(oldValue: oldValue, newValue: notchAppearancePreferences) }
        }
    }

    private var topBarAppearancePreferences = IslandAppearancePreferences() {
        didSet {
            guard topBarAppearancePreferences != oldValue else { return }
            persistAppearancePreferences(topBarAppearancePreferences, for: .topBar)
            if activeAppearanceProfile == .topBar { appearancePreferencesDidChange(oldValue: oldValue, newValue: topBarAppearancePreferences) }
        }
    }

    /// Runtime profile selected from current overlay placement. External
    /// displays use the top-bar presentation; built-in notch displays keep
    /// notch-aware geometry and their own persisted appearance choices.
    var activeAppearanceProfile: IslandAppearanceDisplayProfile {
        overlayPlacementDiagnostics?.mode == .notch ? .notch : .topBar
    }

    var islandRightSlot: IslandRightSlot {
        get { appearancePreferences(for: activeAppearanceProfile).rightSlot }
        set { updateAppearancePreferences(for: activeAppearanceProfile) { $0.rightSlot = newValue } }
    }

    var islandCenterLabel: IslandCenterLabel {
        get { appearancePreferences(for: activeAppearanceProfile).centerLabel }
        set { updateAppearancePreferences(for: activeAppearanceProfile) { $0.centerLabel = newValue } }
    }

    var islandUsageDisplay: IslandUsageDisplay {
        get { appearancePreferences(for: activeAppearanceProfile).usageDisplay }
        set { updateAppearancePreferences(for: activeAppearanceProfile) { $0.usageDisplay = newValue } }
    }

    var islandSessionStateIndicator: IslandSessionStateIndicator {
        get { appearancePreferences(for: activeAppearanceProfile).sessionStateIndicator }
        set { updateAppearancePreferences(for: activeAppearanceProfile) { $0.sessionStateIndicator = newValue } }
    }

    /// A two-way shorthand over the finer appearance choices.
    var menuBarLayout: MenuBarLayout {
        get { MenuBarLayout.resolved(rightSlot: islandRightSlot, centerLabel: islandCenterLabel) }
        set {
            islandRightSlot = newValue.rightSlot
            islandCenterLabel = newValue.centerLabel
        }
    }

    var islandSessionGroup: IslandSessionGroup {
        get { appearancePreferences(for: activeAppearanceProfile).sessionGroup }
        set { updateAppearancePreferences(for: activeAppearanceProfile) { $0.sessionGroup = newValue } }
    }

    var islandSessionSort: IslandSessionSort {
        get { appearancePreferences(for: activeAppearanceProfile).sessionSort }
        set { updateAppearancePreferences(for: activeAppearanceProfile) { $0.sessionSort = newValue } }
    }

    var completedStaleThreshold: IslandCompletedStaleThreshold {
        get { appearancePreferences(for: activeAppearanceProfile).completedStaleThreshold }
        set { updateAppearancePreferences(for: activeAppearanceProfile) { $0.completedStaleThreshold = newValue } }
    }

    @ObservationIgnored
    var openSettingsWindow: (() -> Void)?

    @ObservationIgnored
    private var hasFinishedInit = false

    func appearancePreferences(for profile: IslandAppearanceDisplayProfile) -> IslandAppearancePreferences {
        switch profile {
        case .notch: notchAppearancePreferences
        case .topBar: topBarAppearancePreferences
        }
    }

    func updateAppearancePreferences(
        for profile: IslandAppearanceDisplayProfile,
        _ update: (inout IslandAppearancePreferences) -> Void
    ) {
        switch profile {
        case .notch:
            update(&notchAppearancePreferences)
        case .topBar:
            update(&topBarAppearancePreferences)
        }
    }

    private func appearancePreferencesDidChange(
        oldValue: IslandAppearancePreferences,
        newValue: IslandAppearancePreferences
    ) {
        if oldValue.sessionGroup != newValue.sessionGroup ||
            oldValue.sessionSort != newValue.sessionSort ||
            oldValue.completedStaleThreshold != newValue.completedStaleThreshold {
            _cachedSessionBuckets = nil
        }
        refreshOverlayPlacementIfVisible()
    }

    private func persistAppearancePreferences(
        _ preferences: IslandAppearancePreferences,
        for profile: IslandAppearanceDisplayProfile
    ) {
        let defaults = UserDefaults.standard
        defaults.set(preferences.rightSlot.rawValue, forKey: Self.appearanceDefaultsKey(profile, "rightSlot"))
        defaults.set(preferences.centerLabel.rawValue, forKey: Self.appearanceDefaultsKey(profile, "centerLabel"))
        defaults.set(preferences.usageDisplay.rawValue, forKey: Self.appearanceDefaultsKey(profile, "usageDisplay"))
        defaults.set(preferences.sessionStateIndicator.rawValue, forKey: Self.appearanceDefaultsKey(profile, "stateIndicator"))
        defaults.set(preferences.sessionGroup.rawValue, forKey: Self.appearanceDefaultsKey(profile, "sessionGroup"))
        defaults.set(preferences.sessionSort.rawValue, forKey: Self.appearanceDefaultsKey(profile, "sessionSort"))
        defaults.set(preferences.completedStaleThreshold.rawValue, forKey: Self.appearanceDefaultsKey(profile, "completedStaleThreshold"))
    }

    // MARK: - mitama feed

    private static let mitamaFeedEnabledKey = "mitama.feed.enabled"

    /// Off by default: the island only starts reading mitama's queue once the
    /// owner of that queue asks it to.
    var mitamaFeedEnabled: Bool = false {
        didSet {
            guard mitamaFeedEnabled != oldValue else { return }
            UserDefaults.standard.set(mitamaFeedEnabled, forKey: Self.mitamaFeedEnabledKey)
            if mitamaFeedEnabled {
                mitamaFeed.start()
            } else {
                mitamaFeed.stop()
            }
        }
    }

    let mitamaFeed = MitamaFeedCoordinator()

    func openMitamaHub() {
        NSWorkspace.shared.open(MitamaFeedCoordinator.hubURL)
    }

    // MARK: - Watch Notification

    private static let watchNotificationEnabledKey = "watch.notification.enabled"

    var watchNotificationEnabled: Bool = false {
        didSet {
            guard watchNotificationEnabled != oldValue else { return }
            UserDefaults.standard.set(watchNotificationEnabled, forKey: Self.watchNotificationEnabledKey)
            if watchNotificationEnabled {
                startWatchRelay()
            } else {
                stopWatchRelay()
            }
        }
    }

    @ObservationIgnored
    private(set) var watchRelay: WatchNotificationRelay?

    /// Current pairing code for display in the settings UI.
    var watchPairingCode: String {
        watchRelay?.endpoint.currentCode() ?? "----"
    }

    /// Number of currently connected iPhone SSE clients.
    var watchConnectedDevices: Int {
        // Placeholder — endpoint doesn't expose count yet
        0
    }

    private func startWatchRelay() {
        guard watchRelay == nil else { return }
        let relay = WatchNotificationRelay()
        setupWatchRelayCallbacks(relay)
        relay.start()
        self.watchRelay = relay
    }

    /// Wire up resolution callbacks so Watch/iPhone actions flow back to the bridge.
    private func setupWatchRelayCallbacks(_ relay: WatchNotificationRelay) {
        relay.onResolvePermission = { [weak self] sessionID, approved in
            Task { @MainActor [weak self] in
                self?.approvePermission(for: sessionID, approved: approved)
            }
        }

        relay.onAnswerQuestion = { [weak self] sessionID, answer in
            Task { @MainActor [weak self] in
                self?.answerQuestion(
                    for: sessionID,
                    answer: QuestionPromptResponse(answer: answer)
                )
            }
        }

        relay.endpoint.activeSessionCountProvider = { [weak self] in
            // Safe to call from any queue — reads a snapshot count.
            guard let self else { return 0 }
            return MainActor.assumeIsolated {
                self.state.sessions.count
            }
        }
    }

    private func stopWatchRelay() {
        watchRelay?.stop()
        watchRelay = nil
    }

    var ignoresPointerExitDuringHarness = false
    var disablesOverlayEventMonitoringDuringHarness = false

    @ObservationIgnored
    private var bridgeTask: Task<Void, Never>?

    @ObservationIgnored
    private var bridgeReconnectTask: Task<Void, Never>?

    @ObservationIgnored
    private var hasStarted = false

    @ObservationIgnored
    private let bridgeServer = BridgeServer()

    @ObservationIgnored
    private var bridgeClient = LocalBridgeClient()

    @ObservationIgnored
    private let terminalJumpAction: @Sendable (JumpTarget) throws -> String

    @ObservationIgnored
    private let isNotificationSessionAlreadyFrontmost: @Sendable (AgentSession) async -> Bool


    @ObservationIgnored
    var harnessRuntimeMonitor: HarnessRuntimeMonitor? {
        didSet {
            overlay.harnessRuntimeMonitor = harnessRuntimeMonitor
        }
    }


    @ObservationIgnored
    private var jumpTask: Task<Void, Never>?

    @ObservationIgnored
    private var notificationPresentationTask: Task<Void, Never>?

    private static func appearanceDefaultsKey(_ profile: IslandAppearanceDisplayProfile, _ name: String) -> String {
        "appearance.island.v8.\(profile.rawValue).\(name)"
    }

    private static func loadAppearancePreferences(for profile: IslandAppearanceDisplayProfile) -> IslandAppearancePreferences {
        let defaults = UserDefaults.standard
        return IslandAppearancePreferences(
            rightSlot: IslandRightSlot(
                rawValue: defaults.string(forKey: appearanceDefaultsKey(profile, "rightSlot"))
                    ?? defaults.string(forKey: islandRightSlotDefaultsKey)
                    ?? ""
            ) ?? .count,
            centerLabel: IslandCenterLabel(
                rawValue: defaults.string(forKey: appearanceDefaultsKey(profile, "centerLabel"))
                    ?? defaults.string(forKey: islandCenterLabelDefaultsKey)
                    ?? ""
            ) ?? .agentAction,
            usageDisplay: IslandUsageDisplay(
                rawValue: defaults.string(forKey: appearanceDefaultsKey(profile, "usageDisplay"))
                    ?? ""
            ) ?? .compact,
            sessionStateIndicator: IslandSessionStateIndicator(
                rawValue: defaults.string(forKey: appearanceDefaultsKey(profile, "stateIndicator"))
                    ?? defaults.string(forKey: legacyIslandSessionStateIndicatorDefaultsKey)
                    ?? ""
            ) ?? .animatedDot,
            sessionGroup: IslandSessionGroup(
                rawValue: defaults.string(forKey: appearanceDefaultsKey(profile, "sessionGroup"))
                    ?? defaults.string(forKey: legacyIslandSessionGroupDefaultsKey)
                    ?? ""
            ) ?? .none,
            sessionSort: IslandSessionSort(
                rawValue: defaults.string(forKey: appearanceDefaultsKey(profile, "sessionSort"))
                    ?? defaults.string(forKey: legacyIslandSessionSortDefaultsKey)
                    ?? ""
            ) ?? .attention,
            completedStaleThreshold: IslandCompletedStaleThreshold(
                rawValue: defaults.string(forKey: appearanceDefaultsKey(profile, "completedStaleThreshold"))
                    ?? defaults.string(forKey: legacyCompletedStaleThresholdDefaultsKey)
                    ?? ""
            ) ?? .fiveMinutes
        )
    }

    init(
        terminalJumpAction: @escaping @Sendable (JumpTarget) throws -> String = { target in
            try TerminalJumpService().jump(to: target)
        },
        isNotificationSessionAlreadyFrontmost: @escaping @Sendable (AgentSession) async -> Bool = { session in
            await ForegroundTerminalSessionProbe().matches(session: session)
        },
        settings: SettingsStore = .shared,
        quietScenes: QuietSceneMonitor = QuietSceneMonitor()
    ) {
        self.quietScenes = quietScenes
        self.terminalJumpAction = terminalJumpAction
        self.isNotificationSessionAlreadyFrontmost = isNotificationSessionAlreadyFrontmost
        self.settings = settings
        self.overlay = OverlayUICoordinator(settings: settings)
        UserDefaults.standard.register(defaults: [
            Self.showDockIconDefaultsKey: true,
            Self.hapticFeedbackEnabledDefaultsKey: false,
            Self.completionReplyEnabledDefaultsKey: false,
        ])
        selectedSoundName = NotificationSoundService.selectedSoundName
        showDockIcon = UserDefaults.standard.bool(forKey: Self.showDockIconDefaultsKey)
        hapticFeedbackEnabled = UserDefaults.standard.bool(forKey: Self.hapticFeedbackEnabledDefaultsKey)
        if UserDefaults.standard.object(forKey: Self.showCodexUsageDefaultsKey) != nil {
            showCodexUsage = UserDefaults.standard.bool(forKey: Self.showCodexUsageDefaultsKey)
        } else {
            showCodexUsage = FileManager.default.fileExists(
                atPath: CodexRolloutDiscovery.defaultRootURL.path
            )
        }
        completionReplyEnabled = UserDefaults.standard.bool(forKey: Self.completionReplyEnabledDefaultsKey)
        launchAtLoginEnabled = LaunchAtLoginService.shared.isEnabled
        // An island that only appears when you remember to start it is not a
        // status surface. Register at login on first run of an installed copy;
        // after that the stored answer wins, so turning it off stays off.
        if !launchAtLoginEnabled,
           UserDefaults.standard.object(forKey: Self.launchAtLoginPromptedDefaultsKey) == nil,
           Bundle.main.bundleURL.path.hasPrefix("/Applications/") {
            UserDefaults.standard.set(true, forKey: Self.launchAtLoginPromptedDefaultsKey)
            if (try? LaunchAtLoginService.shared.setEnabled(true)) != nil {
                launchAtLoginEnabled = LaunchAtLoginService.shared.isEnabled
            }
        }
        appearanceSettingsProfile = IslandAppearanceDisplayProfile(
            rawValue: UserDefaults.standard.string(forKey: Self.appearanceProfileSettingsDefaultsKey) ?? ""
        ) ?? .topBar
        notchAppearancePreferences = Self.loadAppearancePreferences(for: .notch)
        topBarAppearancePreferences = Self.loadAppearancePreferences(for: .topBar)
        mitamaFeedEnabled = UserDefaults.standard.bool(forKey: Self.mitamaFeedEnabledKey)
        if mitamaFeedEnabled {
            mitamaFeed.start()
        }
        watchNotificationEnabled = UserDefaults.standard.bool(forKey: Self.watchNotificationEnabledKey)
        if watchNotificationEnabled {
            startWatchRelay()
        }

        quietScenes.start()
        startIdleSessionCleanup()
        hooks.onUsageSnapshotChanged = { [weak self] in
            self?.checkUsageThreshold()
        }

        overlay.appModel = self
        overlay.restoreDisplayPreference()
        overlay.startObservingDisplayChanges()
        overlay.onStatusMessage = { [weak self] message in
            self?.lastActionMessage = message
        }
        overlay.activeIslandCardSessionAccessor = { [weak self] in
            self?.activeIslandCardSession
        }
        overlay.isSoundMutedAccessor = { [weak self] in
            self?.isSoundMuted ?? false
        }
        overlay.ignoresPointerExitAccessor = { [weak self] in
            self?.ignoresPointerExitDuringHarness ?? false
        }
        settings.notificationFilters.onRulesChanged = { [weak self] in
            self?._cachedSessionBuckets = nil
        }
        overlay.hasLiveSessionAccessor = { [weak self] in
            guard let self else { return true }
            return !self.surfacedSessions.isEmpty
        }

        hooks.onStatusMessage = { [weak self] message in
            self?.lastActionMessage = message
        }

        discovery.syntheticClaudeSessionPrefix = Self.syntheticClaudeSessionPrefix
        discovery.onStatusMessage = { [weak self] message in
            self?.lastActionMessage = message
        }
        discovery.stateAccessor = { [weak self] in self?.state ?? SessionState() }
        discovery.stateUpdater = { [weak self] in self?.state = $0 }
        discovery.onStateChanged = { [weak self] in
            self?.synchronizeSelection()
            self?.refreshOverlayPlacementIfVisible()
        }
        discovery.onAgentEvent = { [weak self] event in
            self?.applyTrackedEvent(
                event,
                updateLastActionMessage: false,
                ingress: .rollout
            )
        }

        discovery.codexRolloutWatcher.eventHandler = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.applyTrackedEvent(
                    event,
                    updateLastActionMessage: false,
                    ingress: .rollout
                )
            }
        }

        codexAppServer.onEvent = { [weak self] event in
            self?.applyTrackedEvent(event, ingress: .bridge)
        }
        codexAppServer.onStatusMessage = { [weak self] message in
            self?.lastActionMessage = message
        }
        codexAppServer.isSessionTracked = { [weak self] id in
            self?.state.session(id: id) != nil
        }

        monitoring.syntheticClaudeSessionPrefix = Self.syntheticClaudeSessionPrefix
        monitoring.stateAccessor = { [weak self] in self?.state ?? SessionState() }
        monitoring.stateUpdater = { [weak self] in self?.state = $0 }
        monitoring.onSessionsReconciled = { [weak self] in
            self?.synchronizeSelection()
            self?.refreshOverlayPlacementIfVisible()
        }
        monitoring.onPersistenceNeeded = { [weak self] in
            self?.discovery.scheduleCodexSessionPersistence()
            self?.discovery.scheduleClaudeSessionPersistence()
            self?.discovery.scheduleOpenCodeSessionPersistence()
            self?.discovery.scheduleCursorSessionPersistence()
        }
        monitoring.onCodexAppRunningChanged = { [weak self] isRunning in
            guard let self else { return }
            if isRunning {
                self.codexAppServer.ensureConnected()
            } else {
                self.codexAppServer.disconnect()
            }
        }
        monitoring.onCodexAppMaintenanceTick = { [weak self] in
            self?.discovery.maintainCodexAppSessionsIfNeeded()
        }
        refreshOverlayDisplayConfiguration()
        hasFinishedInit = true
    }

    var sessions: [AgentSession] {
        state.sessions
    }

    var allSessions: [AgentSession] {
        state.sessions
    }

    /// Measured by SwiftUI GeometryReader in notification mode. Used by panel controller for sizing.
    /// Uses a tolerance of 2pt to avoid infinite layout loops caused by floating-point jitter
    /// in GeometryReader measurements across consecutive layout passes.
    var measuredNotificationContentHeight: CGFloat = 0 {
        didSet {
            let delta = abs(measuredNotificationContentHeight - oldValue)
            if delta >= 2, measuredNotificationContentHeight > 0 {
                overlay.refreshOverlayPlacementIfVisible()
            }
        }
    }

    var surfacedSessions: [AgentSession] {
        sessionBuckets.primary
    }

    var recentSessions: [AgentSession] {
        sessionBuckets.overflow
    }

    var islandListSessions: [AgentSession] {
        islandSessionSections.flatMap(\.sessions)
    }

    /// Drops the rows that render grey.
    ///
    /// A finished session nobody is waiting on was still listed, just dimmed — a
    /// thirteen-hour-old row for a directory that no longer means anything. The
    /// island answers "what is happening now", and a greyed row answers a
    /// question it is not asking.
    ///
    /// Uses the same two conditions the row itself uses to go grey, so the list
    /// and the row can never disagree about what counts as quiet.
    ///
    /// Never empties a list that had rows: turning a populated list into an empty
    /// one would read as the app having lost track. (A session that is already
    /// too old to reach this point was never listed to begin with — that is the
    /// bucketing above, not this.)
    private func hidingIdleSessions(_ sessions: [AgentSession]) -> [AgentSession] {
        guard settings.display.hideIdleSessions else { return sessions }
        let now = Date.now
        let threshold = completedStaleThreshold.seconds
        let live = sessions.filter { session in
            session.islandPresence(at: now) != .inactive
                && !session.isStaleCompletedForIsland(at: now, threshold: threshold)
        }
        return live.isEmpty ? sessions : live
    }

    /// Every session the island shows, in no particular order.
    ///
    /// The single source for both the list and the counts. Two derivations of
    /// "what is on the island" is how the badge and the rows came to disagree.
    var islandVisibleSessions: [AgentSession] {
        // Live rows plus anything the registry restored but discovery has not
        // confirmed yet, so a relaunch does not blank the list.
        hidingIdleSessions(surfacedSessions + sessionBuckets.restored)
    }

    var islandSessionSections: [IslandSessionSection] {
        // Live rows plus anything the registry restored but discovery has not
        // confirmed yet, so a relaunch does not blank the list.
        let sessions = sortIslandSessions(islandVisibleSessions)
        switch islandSessionGroup {
        case .none:
            return [
                IslandSessionSection(
                    id: "all",
                    title: "island.section.sessions",
                    sessions: sessions
                )
            ]
        case .state:
            return stateGroupedSections(for: sessions)
        case .agent:
            return AgentTool.allCases.compactMap { tool in
                let list = sessions.filter { $0.tool == tool }
                guard !list.isEmpty else { return nil }
                return IslandSessionSection(id: "agent-\(tool.rawValue)", title: tool.displayName, sessions: list)
            }
        case .project:
            let names = Set(sessions.map(projectGroupName(for:))).sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            }
            return names.compactMap { name in
                let list = sessions.filter { projectGroupName(for: $0) == name }
                guard !list.isEmpty else { return nil }
                return IslandSessionSection(id: "project-\(name)", title: name, sessions: list)
            }
        }
    }

    var recentSessionCount: Int {
        recentSessions.count
    }

    /// What the closed island's count badge says.
    ///
    /// Counts the same set the opened list shows. It used to count
    /// `surfacedSessions`, which still included the rows that had gone grey — so
    /// the pill could read ×5 and open onto two rows.
    var liveSessionCount: Int {
        islandVisibleSessions.count
    }

    var liveAttentionCount: Int {
        surfacedSessions.filter { $0.phase.requiresAttention }.count
    }

    var liveRunningCount: Int {
        surfacedSessions.filter { $0.phase == .running }.count
    }

    private func sortIslandSessions(_ sessions: [AgentSession]) -> [AgentSession] {
        switch islandSessionSort {
        case .attention:
            return sessions
        case .lastUpdate:
            return sessions.sorted { lhs, rhs in
                if lhs.islandActivityDate == rhs.islandActivityDate {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.islandActivityDate > rhs.islandActivityDate
            }
        }
    }

    private func stateGroupedSections(for sessions: [AgentSession]) -> [IslandSessionSection] {
        let definitions: [(id: String, title: String, include: (AgentSession) -> Bool)] = [
            ("approval", "island.section.needsApproval", { $0.phase == .waitingForApproval }),
            ("answer", "island.section.needsAnswer", { $0.phase == .waitingForAnswer }),
            ("running", "island.section.inProgress", { $0.phase == .running }),
            ("done", "island.section.justDone", { [completedStaleThreshold] session in
                session.phase == .completed
                    && !session.isStaleCompletedForIsland(at: .now, threshold: completedStaleThreshold.seconds)
            }),
            ("idle", "island.section.idle", { [completedStaleThreshold] session in
                session.phase == .completed
                    && session.isStaleCompletedForIsland(at: .now, threshold: completedStaleThreshold.seconds)
            }),
        ]

        return definitions.compactMap { definition in
            let list = sessions.filter(definition.include)
            guard !list.isEmpty else { return nil }
            return IslandSessionSection(id: "state-\(definition.id)", title: definition.title, sessions: list)
        }
    }

    private func projectGroupName(for session: AgentSession) -> String {
        if let workspace = session.jumpTarget?.workspaceName.trimmingCharacters(in: .whitespacesAndNewlines),
           !workspace.isEmpty {
            return workspace
        }

        let title = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return session.tool.displayName }

        let pieces = title.split(separator: "·", maxSplits: 1).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return pieces.last?.isEmpty == false ? pieces.last! : title
    }

    // MARK: - v6 closed-island derivation

    /// The aggregate UnifiedBars state for the closed island. Waiting beats
    /// running; everything else is idle. Completed sessions are absorbed
    /// directly into idle so the pill never stops on a tick glyph.
    var islandClosedMode: UnifiedBars.Mode {
        let sessions = surfacedSessions
        if sessions.contains(where: { $0.phase.requiresAttention }) { return .waiting }
        if sessions.contains(where: { $0.phase == .running })       { return .running }
        return .idle
    }

    /// The spotlight session powering the center label (if any). Attention
    /// sessions first, then the most recent running one, then whatever's
    /// first.
    var islandClosedSpotlight: AgentSession? {
        surfacedSessions.first(where: { $0.phase.requiresAttention })
            ?? surfacedSessions.first(where: { $0.phase == .running })
            ?? surfacedSessions.first
    }

    /// Text to show in the closed island's center label. Respects the
    /// `islandCenterLabel` user preference.
    func islandClosedLabel() -> String? {
        guard islandCenterLabel != .off,
              let session = islandClosedSpotlight else { return nil }

        switch islandCenterLabel {
        case .off:
            return nil
        case .sessionName:
            let workspace = session.jumpTarget?.workspaceName ?? ""
            if !workspace.isEmpty { return workspace }
            return session.title.isEmpty ? session.tool.displayName : session.title
        case .agentAction:
            let action = session.displayCurrentToolName
            if let action, !action.isEmpty {
                return "\(session.tool.displayName) · \(action)"
            }
            return session.tool.displayName
        }
    }

    /// Right-slot payload derived from the user's `islandRightSlot`
    /// preference and current live state. Returns nil when the preference
    /// is `.none` or there's nothing meaningful to show.
    func islandClosedRightSlotContent() -> IslandRightSlotContent? {
        let sessions = surfacedSessions
        switch islandRightSlot {
        case .none:
            return nil
        case .count:
            let n = sessions.count
            guard n > 0 else { return nil }
            return .count(n)
        case .agents:
            // Display order = order-of-first-observation-in-the-island. A
            // session that later flips visibility (e.g. attachment churn,
            // completed↔running) keeps its existing slot instead of being
            // reshuffled by session.firstSeenAt, which tracks the historical
            // event time and can be older than visible peers. Bulk-observing
            // N sessions at once (e.g. at app launch) breaks the tie by
            // session.firstSeenAt so historical order is preserved.
            stampAgentsGridObservationTickets(for: sessions)
            let ordered = sessions.sorted { a, b in
                let ta = _agentsGridObservedSequence[a.id] ?? .max
                let tb = _agentsGridObservedSequence[b.id] ?? .max
                if ta != tb { return ta < tb }
                return a.id < b.id
            }
            var cells: [AgentGridCell] = []
            if ordered.count <= 9 {
                cells = ordered.map(Self.agentsGridCell(for:))
            } else {
                cells = ordered.prefix(7).map(Self.agentsGridCell(for:))
                cells.append(.overflow(ordered.count - 7))
            }
            return cells.isEmpty ? nil : .agents(cells)
        }
    }

    private func stampAgentsGridObservationTickets(for sessions: [AgentSession]) {
        let newcomers = sessions.filter { _agentsGridObservedSequence[$0.id] == nil }
        guard !newcomers.isEmpty else { return }
        let orderedNewcomers = newcomers.sorted { a, b in
            if a.firstSeenAt != b.firstSeenAt { return a.firstSeenAt < b.firstSeenAt }
            return a.id < b.id
        }
        for session in orderedNewcomers {
            _agentsGridObservedSequence[session.id] = _agentsGridNextTicket
            _agentsGridNextTicket += 1
        }
    }

    private func pruneAgentsGridObservationTicketsIfNeeded() {
        guard _agentsGridObservedSequence.count > Self.agentsGridObservedSequenceLimit else {
            return
        }

        let liveIDs = Set(state.sessions.map(\.id))
        let retainedHistoricalCapacity = max(Self.agentsGridObservedSequenceLimit - liveIDs.count, 0)
        let retainedHistoricalIDs = _agentsGridObservedSequence
            .filter { !liveIDs.contains($0.key) }
            .sorted { $0.value > $1.value }
            .prefix(retainedHistoricalCapacity)
            .map(\.key)
        let retainedIDs = liveIDs.union(retainedHistoricalIDs)
        _agentsGridObservedSequence = _agentsGridObservedSequence.filter {
            retainedIDs.contains($0.key)
        }
    }

    private static func agentsGridCell(for session: AgentSession) -> AgentGridCell {
        let color = Color(hex: session.tool.brandColorHex) ?? .gray
        let state: AgentGridCellState
        if session.phase.requiresAttention {
            state = .waiting
        } else if session.phase == .running {
            state = .running
        } else {
            state = .idle
        }
        return .session(color: color, state: state)
    }

    var shouldShowSessionBootstrapPlaceholder: Bool {
        isResolvingInitialLiveSessions
            && liveSessionCount == 0
            && state.sessions.contains(where: \.isTrackedLiveSession)
    }

    var focusedSession: AgentSession? {
        state.session(id: selectedSessionID) ?? surfacedSessions.first ?? state.activeActionableSession ?? state.sessions.first
    }

    var activeIslandCardSession: AgentSession? {
        guard let sessionID = islandSurface.sessionID else {
            return nil
        }

        return state.session(id: sessionID)
    }

    var hasAnySession: Bool {
        !sessions.isEmpty
    }

    var hasCodexSession: Bool {
        sessions.contains(where: { $0.tool == .codex })
    }

    var hasJumpableSession: Bool {
        sessions.contains(where: { $0.jumpTarget != nil })
    }

    var acceptanceSteps: [AcceptanceStep] {
        [
            AcceptanceStep(
                id: "bridge",
                title: "Bridge ready",
                detail: "The app must own the local socket and register as a bridge observer.",
                isComplete: isBridgeReady
            ),
            AcceptanceStep(
                id: "hooks",
                title: "Codex hooks installed",
                detail: "Managed `hooks.json` entries should be present in `~/.codex`.",
                isComplete: hooks.codexHooksInstalled
            ),
            AcceptanceStep(
                id: "overlay",
                title: "Island visible",
                detail: "Show the overlay at least once so the notch/top-bar surface is visible.",
                isComplete: isOverlayVisible
            ),
            AcceptanceStep(
                id: "session",
                title: "A Codex session is observed",
                detail: "Start Codex in Terminal and wait for the first session row to appear.",
                isComplete: hasCodexSession
            ),
            AcceptanceStep(
                id: "jump",
                title: "Jump target captured",
                detail: "At least one session should include terminal jump metadata.",
                isComplete: hasJumpableSession
            ),
        ]
    }

    var acceptanceCompletedCount: Int {
        acceptanceSteps.filter(\.isComplete).count
    }

    var isReadyForFirstAcceptance: Bool {
        acceptanceSteps.prefix(3).allSatisfy(\.isComplete)
    }

    var hasPassedAcceptanceFlow: Bool {
        acceptanceSteps.allSatisfy(\.isComplete)
    }

    var acceptanceStatusTitle: String {
        if hasPassedAcceptanceFlow {
            return "v0.1 acceptance passed"
        }

        if isReadyForFirstAcceptance {
            return "Ready for v0.1 acceptance"
        }

        return "v0.1 acceptance not ready"
    }

    var acceptanceStatusSummary: String {
        if hasPassedAcceptanceFlow {
            return "The current build has completed the first-run checklist end to end."
        }

        if isReadyForFirstAcceptance {
            return "You can start your first acceptance run now. Launch Codex in Terminal and walk the last two steps."
        }

        return "Finish the setup steps in the left column, then start Codex from Terminal."
    }

    func startIfNeeded(
        startBridge: Bool = true,
        shouldPerformBootAnimation: Bool = true,
        loadRuntimeState: Bool = true
    ) {
        guard !hasStarted else {
            return
        }
        hasStarted = true

        // Hot keys are registered process-wide. A harness run would take them
        // away from the copy the user is actually using.
        if !disablesOverlayEventMonitoringDuringHarness {
            startPanelHotkeys()
        }

        if loadRuntimeState {
            isResolvingInitialLiveSessions = true

            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                // Two passes so the island fills in immediately: the
                // registries first, then the filesystem scan that can take
                // tens of seconds on a large ~/.claude/projects.
                let persisted = self.discovery.loadPersistedSessionPayload()
                await MainActor.run {
                    self.applyStartupDiscoveryPayload(persisted)
                }

                let full = self.discovery.loadStartupDiscoveryPayload()
                await MainActor.run {
                    self.applyStartupDiscoveryPayload(full)
                }
            }

            // These are already async or lightweight — safe to start immediately.
            hooks.refreshCodexHookStatus()
            hooks.refreshClaudeHookStatus()
            hooks.refreshCCForkHookStatuses()
            hooks.refreshOpenCodePluginStatus()
            hooks.refreshCursorHookStatus()
            hooks.refreshClaudeUsageState()
            hooks.startClaudeUsageMonitoringIfNeeded()
            if showCodexUsage {
                hooks.refreshCodexUsageState()
                hooks.startCodexUsageMonitoringIfNeeded()
            }
            updateChecker.startIfNeeded()

        } else {
            isResolvingInitialLiveSessions = false
        }
        refreshOverlayDisplayConfiguration()
        ensureOverlayPanel()
        if shouldPerformBootAnimation {
            performBootAnimation()
        }

        guard startBridge else {
            isBridgeReady = false
            lastActionMessage = loadRuntimeState
                ? "Harness mode active. Bridge startup skipped."
                : "Deterministic harness mode active. Runtime discovery and bridge startup skipped."
            harnessRuntimeMonitor?.recordMilestone("bridgeSkipped", message: lastActionMessage)
            return
        }

        do {
            try bridgeServer.start()
            connectBridgeObserver()
        } catch {
            isBridgeReady = false
            lastActionMessage = "Failed to start local bridge: \(error.localizedDescription)"
            harnessRuntimeMonitor?.recordMilestone("bridgeStartFailed", message: lastActionMessage)
        }
    }

    // MARK: - Bridge observer connection

    private static let bridgeReconnectDelay: Duration = .seconds(2)
    private static let bridgeMaxReconnectDelay: Duration = .seconds(30)

    private func connectBridgeObserver() {
        bridgeTask?.cancel()
        bridgeReconnectTask?.cancel()

        // Explicitly disconnect the old client so its DispatchSource is
        // cancelled deterministically rather than relying on dealloc timing.
        bridgeClient.disconnect()

        // Create a fresh client for each connection attempt so we don't
        // have to worry about stale file-descriptor state.
        let client = LocalBridgeClient()
        bridgeClient = client

        let stream: AsyncThrowingStream<AgentEvent, Error>
        do {
            stream = try client.connect()
        } catch {
            isBridgeReady = false
            lastActionMessage = "Failed to connect bridge observer: \(error.localizedDescription)"
            scheduleBridgeReconnect()
            return
        }

        // A single task handles both registration and event consumption so
        // there is no untracked task that could race with a reconnect.
        bridgeTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await client.send(.registerClient(role: .observer))
                self.isBridgeReady = true
                self.lastActionMessage = "Bridge ready. Waiting for Claude and Codex hook events."
                self.harnessRuntimeMonitor?.recordMilestone("bridgeReady", message: self.lastActionMessage)
            } catch {
                guard !Task.isCancelled else { return }
                self.isBridgeReady = false
                self.lastActionMessage = "Failed to register bridge observer: \(error.localizedDescription)"
                self.harnessRuntimeMonitor?.recordMilestone(
                    "bridgeRegistrationFailed",
                    message: self.lastActionMessage
                )
                self.scheduleBridgeReconnect()
                return
            }

            do {
                for try await event in stream {
                    self.applyTrackedEvent(event)
                }
            } catch {}

            // Stream ended (server closed our connection or transient error).
            // Mark as disconnected and schedule reconnection.
            guard !Task.isCancelled else { return }
            self.isBridgeReady = false
            self.lastActionMessage = "Bridge observer disconnected. Reconnecting…"
            self.harnessRuntimeMonitor?.recordMilestone("bridgeDisconnected", message: self.lastActionMessage)
            self.scheduleBridgeReconnect()
        }
    }

    private func scheduleBridgeReconnect() {
        bridgeReconnectTask?.cancel()
        bridgeReconnectTask = Task { [weak self] in
            var delay = Self.bridgeReconnectDelay
            while !Task.isCancelled {
                try? await Task.sleep(for: delay)
                guard let self, !Task.isCancelled else { return }
                self.connectBridgeObserver()
                // If we're now connected, stop retrying.
                if self.isBridgeReady { return }
                delay = min(delay * 2, Self.bridgeMaxReconnectDelay)
            }
        }
    }

    func select(sessionID: String) {
        selectedSessionID = sessionID
    }

    // MARK: - Overlay forwarding

    func toggleOverlay() { overlay.toggleOverlay() }
    func notchOpen(reason: NotchOpenReason, surface: IslandSurface = .sessionList()) { overlay.notchOpen(reason: reason, surface: surface) }
    func notchClose() { overlay.notchClose() }
    func notchPop() { overlay.notchPop() }
    func performBootAnimation() { overlay.performBootAnimation() }
    func ensureOverlayPanel() { overlay.ensureOverlayPanel() }
    func showOverlay() { overlay.showOverlay() }
    func hideOverlay() { overlay.hideOverlay() }
    func expandNotificationToSessionList(clearExpansion: Bool = false) {
        overlay.expandNotificationToSessionList(clearExpansion: clearExpansion)
    }
    func refreshOverlayDisplayConfiguration() { overlay.refreshOverlayDisplayConfiguration() }
    func refreshOverlayPlacement() { overlay.refreshOverlayPlacement() }
    private func refreshOverlayPlacementIfVisible() { overlay.refreshOverlayPlacementIfVisible() }
    func notePointerInsideIslandSurface() { overlay.notePointerInsideIslandSurface() }
    func handlePointerExitedIslandSurface() { overlay.handlePointerExitedIslandSurface() }
    private func presentNotificationSurface(_ surface: IslandSurface) { overlay.presentNotificationSurface(surface) }
    private func reconcileIslandSurfaceAfterStateChange() { overlay.reconcileIslandSurfaceAfterStateChange() }
    func dismissNotificationSurfaceIfPresent(for sessionID: String) { overlay.dismissNotificationSurfaceIfPresent(for: sessionID) }
    private func dismissOverlayForJump() { overlay.dismissOverlayForJump() }

    var shouldAutoCollapseOnMouseLeave: Bool { overlay.shouldAutoCollapseOnMouseLeave }
    var autoCollapseOnMouseLeaveRequiresPriorSurfaceEntry: Bool { overlay.autoCollapseOnMouseLeaveRequiresPriorSurfaceEntry }

    var islandMayBeVisible: Bool { overlay.islandMayBeVisible }
    var showsNotificationCard: Bool { overlay.showsNotificationCard }
    var shouldDeferTimedNotificationAutoCollapse: Bool { overlay.shouldDeferTimedNotificationAutoCollapse }
    var hasPendingNotificationAutoCollapse: Bool { overlay.hasPendingNotificationAutoCollapse }

    func loadDebugSnapshot(
        _ snapshot: IslandDebugSnapshot,
        presentOverlay: Bool = false,
        autoCollapseNotificationCards: Bool = false
    ) {
        state = SessionState(sessions: snapshot.sessions)
        selectedSessionID = snapshot.selectedSessionID ?? snapshot.sessions.first?.id
        lastActionMessage = "Loaded debug scenario: \(snapshot.title)."
        harnessRuntimeMonitor?.recordMilestone("scenarioLoaded", message: snapshot.title)

        overlay.applyOverlayState(from: snapshot, presentOverlay: presentOverlay, autoCollapseNotificationCards: autoCollapseNotificationCards)

        if let banner = snapshot.completionBanner {
            // The same open handler production uses, so what the harness
            // captures is what ships — including the affordance that says the
            // banner leads somewhere.
            completionBanner.present(
                banner,
                on: overlay.overlayPanelController.currentOverlayScreen,
                onOpen: { [weak self] sessionID in
                    self?.openCompletionSummary(for: sessionID)
                }
            )
        }
    }

    func showSettings() {
        if let opener = openSettingsWindow {
            opener()
        } else {
            // First-launch fallback: SwiftUI's `openWindow` closure is registered
            // by `SettingsWindowContent.onAppear`, which doesn't fire until the
            // settings window renders the first time. Send the standard
            // `showSettingsWindow:` responder action (macOS 13+) so it fires
            // the `CommandGroup(.appSettings)` button that opens the window.
            NSApp.sendAction(NSSelectorFromString("showSettingsWindow:"), to: nil, from: nil)
        }
        if let window = NSApp.windows.first(where: { $0.title == "Open Island Settings" }) {
            window.orderFrontRegardless()
            window.makeKey()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Opens Settings on the Setup tab so the user can install hooks.
    /// Used by every "Set up agents" CTA in the empty-state UI. A
    /// dedicated first-run onboarding window will replace this in a
    /// later PR; until then this is the canonical entry point.
    func showOnboarding() {
        showSettings()
        NotificationCenter.default.post(name: .openIslandSelectSetupTab, object: nil)
    }

    func showSettings(tab rawValue: String) {
        showSettings()
        NotificationCenter.default.post(name: .openIslandSelectSettingsTab, object: rawValue)
    }

    func toggleSoundMuted() {
        isSoundMuted.toggle()
    }

    func approveFocusedPermission(_ approved: Bool) {
        guard let session = focusedSession else {
            return
        }

        send(
            .resolvePermission(sessionID: session.id, resolution: permissionResolution(for: approved)),
            userMessage: approved
                ? "Approving permission for \(session.title)."
                : "Denying permission for \(session.title)."
        )
    }

    func answerFocusedQuestion(_ answer: String) {
        guard let session = focusedSession else {
            return
        }

        send(
            .answerQuestion(sessionID: session.id, response: QuestionPromptResponse(answer: answer)),
            userMessage: "Sending answer \"\(answer)\" for \(session.title)."
        )
    }

    func jumpToFocusedSession() {
        jump(to: focusedSession?.jumpTarget)
    }

    func jumpToSession(_ session: AgentSession) {
        // Only the row tap goes through here. Explicit "go to terminal" buttons
        // call `jump(to:)` directly and stay available either way.
        guard !settings.behaviour.disableClickToJump else { return }

        guard let jumpTarget = session.jumpTarget,
              jumpTarget.terminalApp.lowercased() != "unknown" else {
            lastActionMessage = "Cannot jump: terminal app is unknown."
            return
        }
        jump(to: jumpTarget)
    }

    private func jump(to jumpTarget: JumpTarget?) {
        guard let jumpTarget else {
            lastActionMessage = "No jump target is available yet."
            return
        }

        let shouldDelayForDismissAnimation = isOverlayVisible
        let jumpAction = terminalJumpAction

        dismissOverlayForJump()
        jumpTask?.cancel()
        jumpTask = Task { [weak self] in
            if shouldDelayForDismissAnimation {
                try? await Task.sleep(for: Self.jumpOverlayDismissLeadTime)
            }

            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try jumpAction(jumpTarget)
                }.value

                guard !Task.isCancelled else {
                    return
                }

                self?.lastActionMessage = result
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                self?.lastActionMessage = "Jump failed: \(error.localizedDescription)"
            }
        }
    }

    func approvePermission(for sessionID: String, approved: Bool) {
        guard let session = state.session(id: sessionID) else {
            return
        }

        let resolution = permissionResolution(for: approved)
        dismissNotificationSurfaceIfPresent(for: sessionID)
        state.resolvePermission(sessionID: session.id, resolution: resolution)
        synchronizeSelection()
        refreshOverlayPlacementIfVisible()

        send(
            .resolvePermission(sessionID: session.id, resolution: resolution),
            userMessage: approved
                ? "Approving permission for \(session.title)."
                : "Denying permission for \(session.title)."
        )
    }

    /// Sessions blocked on a permission decision right now.
    var pendingApprovalSessions: [AgentSession] {
        surfacedSessions.filter { $0.permissionRequest != nil && $0.phase == .waitingForApproval }
    }

    /// Answers every blocked session the same way.
    ///
    /// Each one still goes through `approvePermission`, so the resolution and
    /// the message the agent receives are identical to answering them one by one.
    func resolveAllPendingApprovals(_ action: ApprovalAction) {
        for session in pendingApprovalSessions {
            approvePermission(for: session.id, action: action)
        }
    }

    func approvePermission(for sessionID: String, action: ApprovalAction) {
        guard let session = state.session(id: sessionID) else {
            return
        }

        let resolution: PermissionResolution
        let message: String

        switch action {
        case .deny:
            resolution = .deny(message: "Permission denied in Open Island.", interrupt: false)
            message = "Denying permission for \(session.title)."
        case .allowOnce:
            resolution = .allowOnce()
            message = "Approving permission for \(session.title)."
        case let .allowWithUpdates(updates):
            resolution = .allowOnce(updatedPermissions: updates)
            message = "Always allowing for \(session.title)."
        }

        dismissNotificationSurfaceIfPresent(for: sessionID)
        state.resolvePermission(sessionID: session.id, resolution: resolution)
        synchronizeSelection()
        refreshOverlayPlacementIfVisible()

        send(
            .resolvePermission(sessionID: session.id, resolution: resolution),
            userMessage: message
        )
    }

    func dismissSession(_ sessionID: String) {
        state.dismissSession(id: sessionID)
        dismissNotificationSurfaceIfPresent(for: sessionID)
        synchronizeSelection()
    }

    func answerQuestion(for sessionID: String, answer: QuestionPromptResponse) {
        guard let session = state.session(id: sessionID) else {
            return
        }

        dismissNotificationSurfaceIfPresent(for: sessionID)
        state.answerQuestion(sessionID: session.id, response: answer)
        synchronizeSelection()
        refreshOverlayPlacementIfVisible()

        send(
            .answerQuestion(sessionID: session.id, response: answer),
            userMessage: "Sending answer for \(session.title)."
        )
    }

    func replyToSession(_ session: AgentSession, text: String) {
        dismissNotificationSurfaceIfPresent(for: session.id)
        synchronizeSelection()
        refreshOverlayPlacementIfVisible()

        lastActionMessage = "Sending reply to \(session.title)…"

        Task { [weak self] in
            let success = await Task.detached(priority: .userInitiated) {
                TerminalTextSender.send(text, to: session)
            }.value

            self?.lastActionMessage = success
                ? "Sent reply to \(session.title)."
                : "Failed to send reply to \(session.title)."
        }
    }


    private func send(_ command: BridgeCommand, userMessage: String) {
        lastActionMessage = userMessage

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                try await self.bridgeClient.send(command)
            } catch {
                self.lastActionMessage = "Failed to send bridge command: \(error.localizedDescription)"
            }
        }
    }

    private func permissionResolution(for approved: Bool) -> PermissionResolution {
        if approved {
            return .allowOnce()
        }

        return .deny(message: "Permission denied in Open Island.", interrupt: false)
    }

    func applyTrackedEvent(
        _ event: AgentEvent,
        updateLastActionMessage: Bool = true,
        ingress: TrackedEventIngress = .bridge
    ) {
        // Snapshot whether this session was already completed before applying
        // the event. Used to suppress duplicate/stale completion notifications
        // (e.g. rollout watcher re-discovering an old completion on startup,
        // or producing a duplicate sessionCompleted that races with the bridge).
        let wasAlreadyCompleted: Bool = {
            guard case let .sessionCompleted(payload) = event else { return false }
            return state.session(id: payload.sessionID)?.phase == .completed
        }()

        // Guard: don't let rollout events downgrade a session from completed
        // back to running. The bridge's sessionCompleted is authoritative; the
        // rollout watcher may have read the JSONL before task_complete was
        // flushed, producing a stale activityUpdated(phase: .running).
        if ingress == .rollout,
           case let .activityUpdated(payload) = event,
           payload.phase == .running,
           state.session(id: payload.sessionID)?.phase == .completed {
            return
        }

        state.apply(event)
        reconcileIslandSurfaceAfterStateChange()
        if ingress == .bridge {
            monitoring.markSessionAttached(for: event)
            monitoring.markSessionProcessAlive(for: event)
        }
        synchronizeSelection()
        discovery.refreshCodexRolloutTracking()
        refreshOverlayPlacementIfVisible()
        discovery.scheduleCodexSessionPersistence()
        discovery.scheduleClaudeSessionPersistence()
        discovery.scheduleOpenCodeSessionPersistence()
        discovery.scheduleCursorSessionPersistence()

        // Push relevant events to the Watch/iPhone via the relay
        if let relay = watchRelay {
            let eventSessionID: String? = {
                switch event {
                case let .sessionStarted(p): return p.sessionID
                case let .activityUpdated(p): return p.sessionID
                case let .permissionRequested(p): return p.sessionID
                case let .questionAsked(p): return p.sessionID
                case let .sessionCompleted(p): return p.sessionID
                case let .jumpTargetUpdated(p): return p.sessionID
                case let .sessionMetadataUpdated(p): return p.sessionID
                case let .claudeSessionMetadataUpdated(p): return p.sessionID
                case let .geminiSessionMetadataUpdated(p): return p.sessionID
                case let .openCodeSessionMetadataUpdated(p): return p.sessionID
                case let .cursorSessionMetadataUpdated(p): return p.sessionID
                case let .actionableStateResolved(p): return p.sessionID
                }
            }()
            let session = eventSessionID.flatMap { state.session(id: $0) }
            relay.notifyEvent(event, session: session)
        }

        if updateLastActionMessage {
            lastActionMessage = describe(event)
        }

        playSoundIfRaisedOutsideACard(for: event)
        presentCompletionBannerIfWanted(for: event)

        if let surface = IslandSurface.notificationSurface(for: event),
           shouldNotify(about: event) {
            scheduleNotificationSurfacePresentationIfNeeded(
                surface,
                wasAlreadyCompleted: wasAlreadyCompleted,
                ingress: ingress
            )
        }
    }

    // MARK: Completion banner

    let completionBanner = CompletionBannerController()

    /// Announces a finished session in the middle of the screen.
    ///
    /// Deliberately silent: `taskComplete` already plays from the notification
    /// card path, and two sounds for one event reads as a bug.
    /// Whether this finished session gets a banner.
    ///
    /// One predicate for both decisions — showing the banner, and holding back
    /// the panel that would otherwise duplicate it. Two copies of this rule
    /// would eventually disagree and bring back the double announcement.
    private func completionBannerApplies(to payload: SessionCompleted) -> Bool {
        settings.display.completionBanner
            && payload.isInterrupt != true
            && !quietScenes.shouldStayQuiet(under: settings.behaviour)
            && state.session(id: payload.sessionID) != nil
    }

    private func presentCompletionBannerIfWanted(for event: AgentEvent) {
        guard case let .sessionCompleted(payload) = event,
              completionBannerApplies(to: payload),
              let session = state.session(id: payload.sessionID) else {
            return
        }

        completionBanner.present(
            CompletionBannerContent(
                sessionID: session.id,
                title: session.spotlightWorkspaceName,
                agentName: session.tool.displayName,
                duration: CompletionDurationFormatter.string(
                    for: payload.timestamp.timeIntervalSince(session.firstSeenAt)
                )
            ),
            on: overlay.overlayPanelController.currentOverlayScreen,
            onOpen: { [weak self] sessionID in
                self?.openCompletionSummary(for: sessionID)
            }
        )
    }

    /// Opens the island on the session the banner is announcing.
    ///
    /// The banner says *that* it finished; the panel says what it did. Keeping
    /// the second behind a click is what stops a finished session from taking
    /// over the screen on its own.
    func openCompletionSummary(for sessionID: String) {
        guard state.session(id: sessionID) != nil else {
            // Nothing to open. Take the banner away rather than leaving an
            // announcement that leads nowhere.
            completionBanner.dismiss()
            return
        }

        // The panel starts opening while the banner is still travelling up into
        // the notch, so the two overlap instead of following one another.
        selectedSessionID = sessionID
        overlay.notchOpen(
            reason: .notification,
            surface: .sessionList(actionableSessionID: sessionID)
        )
        completionBanner.dismissHandingOff()
    }

    /// Sounds for the moments that never open a card.
    ///
    /// Approvals, questions and completions chime from the card that presents
    /// them. These two have no card, so they are raised here — and only when a
    /// scene the user marked quiet is not in effect, so one route cannot end up
    /// louder than the other.
    private func playSoundIfRaisedOutsideACard(for event: AgentEvent) {
        guard !quietScenes.shouldStayQuiet(under: settings.behaviour) else { return }
        switch event {
        case .sessionStarted:
            NotificationSoundService.play(.sessionStart, settings: settings.sound)
        case let .activityUpdated(payload) where payload.isCompacting:
            NotificationSoundService.play(.contextLimit, settings: settings.sound)
        default:
            break
        }
    }

    /// Whether this event is worth interrupting the user for.
    ///
    /// Approvals and questions always are — nothing proceeds until they answer.
    /// A finished session is only worth a panel if they asked for that.
    private func shouldNotify(about event: AgentEvent) -> Bool {
        // Focus, a locked screen and a shared screen suppress the panel only.
        // The Watch relay still fires: a locked Mac is exactly when the wrist is
        // the surface that works.
        if quietScenes.shouldStayQuiet(under: settings.behaviour) { return false }
        switch event {
        case let .sessionCompleted(payload):
            // The banner and the card used to arrive together for the same
            // finished session: an announcement under the notch, and the notch
            // opening behind it with the summary. One event, two things to
            // dismiss. The banner is the announcement now, and opening it is
            // what brings up the summary.
            if completionBannerApplies(to: payload) { return false }
            return settings.behaviour.expandOnCompletion
        default:
            return true
        }
    }

    private let idleCleanupTimerBox = RepeatingTimerBox()

    // MARK: Custom sounds

    private let customSounds = CustomSoundLibrary(directory: CustomSoundLibrary.defaultDirectory())

    /// Bumped after an import or a removal so the settings list redraws.
    private var customSoundsRevision = 0

    var customSoundNames: [String] {
        _ = customSoundsRevision
        return customSounds.soundNames()
    }

    func importCustomSounds() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.audio]
        guard panel.runModal() == .OK else { return }

        do {
            let imported = try customSounds.importSounds(from: panel.urls)
            customSoundsRevision += 1
            lastActionMessage = imported.isEmpty
                ? lang.t("settings.sound.import.none")
                : lang.t("settings.sound.import.done")
                    .replacingOccurrences(of: "{count}", with: "\(imported.count)")
        } catch {
            lastActionMessage = error.localizedDescription
        }
    }

    /// Whether the one-time introduction still has to run.
    ///
    /// A Mac that already has hooks installed is not a first launch even if this
    /// copy of the app has never run — `migrateFromLegacyStateIfNeeded` marks it
    /// completed, so an existing user is never shown an introduction.
    var needsOnboarding: Bool { !firstLaunchCompleted }

    func completeOnboarding() {
        firstLaunchCompleted = true
        closeOnboardingWindow?()
    }

    var closeOnboardingWindow: (() -> Void)?
    var presentOnboarding: (() -> Void)?

    /// The agents actually present on this Mac, for the detection screen.
    var installedAgentDisplayNames: [String] {
        hooks.intentStore.installedAgents().map(\.displayName)
    }

    // MARK: Keyboard

    /// Nil during a harness run: registering process-global hot keys from a
    /// screenshot process would take them away from the real app.
    private(set) var panelHotkeys: PanelHotkeyCoordinator?

    /// Reveals each button's letter while the modifier is held.
    let shortcutHints = ShortcutHintMonitor()

    // MARK: Switcher

    private(set) var switcher = SwitcherState()

    /// The sessions the switcher cycles through, in the order they are shown.
    private var switcherSessionIDs: [String] {
        state.sessions.filter(\.isVisibleInIsland).map(\.id)
    }

    /// One press of the switcher key: opens it, or moves along if already open.
    func toggleSwitcher(reversed: Bool) {
        let ids = switcherSessionIDs
        guard ids.count > 1 else { return }

        if switcher.isActive {
            switcher.advance(sessions: ids, reversed: reversed)
        } else {
            switcher.open(
                sessions: ids,
                current: activeIslandCardSession?.id ?? ids.first,
                at: .now,
                reversed: reversed
            )
            overlay.notchOpen(reason: .switcher)
        }
        panelHotkeys?.switcherDidActivate()
    }

    /// The modifier came up. A hold ends in a jump; a tap leaves the list open
    /// so the arrow keys can be used instead.
    func switcherModifierReleased() {
        guard let targetID = switcher.modifierReleased(at: .now) else { return }
        finishSwitcher(jumpingTo: targetID)
    }

    func switcherMoveSelection(reversed: Bool) {
        switcher.moveSelection(sessions: switcherSessionIDs, reversed: reversed)
    }

    func switcherConfirm() {
        guard let targetID = switcher.confirm() else { return }
        finishSwitcher(jumpingTo: targetID)
    }

    func switcherCancel() {
        switcher.cancel()
        panelHotkeys?.switcherDidDeactivate()
        overlay.notchClose()
    }

    private func finishSwitcher(jumpingTo sessionID: String) {
        panelHotkeys?.switcherDidDeactivate()
        overlay.notchClose()
        guard let session = state.session(id: sessionID) else { return }
        jump(to: session.jumpTarget)
    }

    private func startPanelHotkeys() {
        shortcutHints.start(modifier: settings.shortcuts.modifier)
        shortcutHints.onModifierReleased = { [weak self] in
            self?.switcherModifierReleased()
        }
        let coordinator = PanelHotkeyCoordinator(
            registrar: CarbonHotkeyController(),
            settings: settings.shortcuts
        )
        coordinator.onAction = { [weak self] action in
            self?.performShortcut(action)
        }
        coordinator.onSwitcherKey = { [weak self] reversed in
            self?.toggleSwitcher(reversed: reversed)
        }
        coordinator.onSwitcherNavigate = { [weak self] reversed in
            self?.switcherMoveSelection(reversed: reversed)
        }
        coordinator.onSwitcherConfirm = { [weak self] in
            self?.switcherConfirm()
        }
        coordinator.onSwitcherCancel = { [weak self] in
            self?.switcherCancel()
        }
        coordinator.startPersistentBindings()
        panelHotkeys = coordinator
    }

    /// Applies a shortcut to whatever the panel is currently asking about.
    ///
    /// Falls back to the first session waiting on the user when no card is
    /// showing, so ⌃Y works from a list as well as from a card.
    func performShortcut(_ action: PanelShortcutAction) {
        guard let session = activeIslandCardSession ?? pendingApprovalSessions.first else { return }

        switch action {
        case .approve:
            approvePermission(for: session.id, action: .allowOnce)
        case .deny:
            approvePermission(for: session.id, action: .deny)
        case .alwaysAllow:
            approvePermission(for: session.id, action: alwaysAllowAction(for: session))
        case .skipPermissions:
            approvePermission(for: session.id, action: bypassAction(for: session))
        case .jumpToTerminal:
            jumpToSession(session)
        }
    }

    /// The update the agent offered for "always allow", if it offered one.
    /// Without it there is nothing to remember, so this falls back to one-off
    /// approval rather than claiming a permission was stored.
    private func alwaysAllowAction(for session: AgentSession) -> ApprovalAction {
        let updates = session.permissionRequest?.suggestedUpdates ?? []
        guard let rule = updates.first(where: { $0.isRuleAddition }) else { return .allowOnce }
        return .allowWithUpdates([rule])
    }

    private func bypassAction(for session: AgentSession) -> ApprovalAction {
        let updates = session.permissionRequest?.suggestedUpdates ?? []
        guard let bypass = updates.first(where: { $0.isModeChange }) else { return .allowOnce }
        return .allowWithUpdates([bypass])
    }

    var islandTheme: IslandThemeID {
        get { IslandThemeID(rawValue: settings.display.themeRawValue) ?? .hud }
        set { settings.display.themeRawValue = newValue.rawValue }
    }

    var agentIconStyle: AgentIconStyle {
        get { AgentIconStyle(rawValue: settings.display.agentIconStyleRawValue) ?? .pixel }
        set { settings.display.agentIconStyleRawValue = newValue.rawValue }
    }

    /// Sessions that were already running when hooks were last installed.
    ///
    /// Only live ones count. A session that has since finished cannot be
    /// restarted and telling the user to restart it would be noise.
    var sessionsPredatingHookInstall: [AgentSession] {
        guard let installedAt = hooks.intentStore.lastHookInstallDate else { return [] }
        return state.sessions.filter {
            $0.firstSeenAt < installedAt && $0.phase != .completed && $0.isVisibleInIsland
        }
    }

    /// Writes a diagnostics file and reveals it, so it can be attached to a
    /// bug report. Nothing leaves the machine on its own.
    func exportDiagnostics() {
        let report = DiagnosticsReport(
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            installedAgents: installedAgentDisplayNames,
            sessions: state.sessions.map { session in
                DiagnosticsReport.SessionLine(
                    tool: session.tool.displayName,
                    phase: String(describing: session.phase),
                    terminalApp: session.jumpTarget?.terminalApp,
                    isVisible: session.isVisibleInIsland
                        && !settings.notificationFilters.isSilenced(session),
                    updatedSecondsAgo: Int(Date.now.timeIntervalSince(session.updatedAt))
                )
            },
            activeFilterCount: settings.notificationFilters.activeRules.count,
            quietScenes: activeQuietSceneNames,
            generatedAt: .now
        )

        do {
            let url = try report.write(to: FileManager.default.temporaryDirectory)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            lastActionMessage = lang.t("settings.general.diagnostics.written")
        } catch {
            lastActionMessage = error.localizedDescription
        }
    }

    /// Which of the quiet scenes is in effect right now, named plainly.
    private var activeQuietSceneNames: [String] {
        var names: [String] = []
        let snapshot = quietScenes.snapshot
        if let modes = snapshot.activeFocusModes, !modes.isEmpty {
            names.append("focus: \(modes.sorted().joined(separator: "+"))")
        }
        if snapshot.screenIsObscured.isActive { names.append("screen locked") }
        if snapshot.screenIsBeingShared.isActive { names.append("screen sharing app open") }
        return names
    }

    /// Adds a filter rule from the island's right-click menu.
    ///
    /// Deduplicated, because right-clicking the same folder twice should not
    /// leave two identical rules for the user to delete one by one.
    func hideSessions(matching rule: SilenceRule) {
        let filters = settings.notificationFilters
        let alreadyPresent = filters.customRules.contains {
            $0.field == rule.field && $0.match == rule.match
                && $0.pattern.caseInsensitiveCompare(rule.pattern) == .orderedSame
        }
        guard !alreadyPresent else { return }
        filters.customRules.append(rule)
        lastActionMessage = lang.t("island.session.hidden")
            .replacingOccurrences(of: "{pattern}", with: rule.pattern)
    }

    func removeCustomSound(named name: String) {
        do {
            try customSounds.removeSound(named: name)
            customSoundsRevision += 1
        } catch {
            lastActionMessage = error.localizedDescription
        }
    }

    func previewSound(named name: String) {
        NotificationSoundService.play(name, volume: settings.sound.volume)
    }

    /// Sweeps out sessions nobody is waiting on.
    ///
    /// Runs on a slow timer rather than on every event: the point is to clear
    /// rows that stopped changing, and nothing arrives to trigger that.
    private func startIdleSessionCleanup() {
        let timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pruneIdleSessions() }
        }
        timer.tolerance = 60
        idleCleanupTimerBox.timer = timer
    }

    @discardableResult
    func pruneIdleSessions(now: Date = .now) -> [String] {
        guard let interval = settings.behaviour.idleSessionCleanup.interval else { return [] }
        let removed = state.pruneIdleSessions(olderThan: interval, now: now)
        for id in removed {
            // A card left on screen for a session that no longer exists would
            // have no working buttons.
            dismissNotificationSurfaceIfPresent(for: id)
        }
        return removed
    }

    /// Tracks which usage windows have already been warned about.
    private var usageThresholdMonitor = UsageThresholdMonitor(threshold: 0)

    /// Raises one card per window that crosses the user's threshold.
    ///
    /// Deliberately not a repeating warning: a quota that stays over 80% for
    /// four hours would otherwise nag on every refresh.
    func checkUsageThreshold() {
        let threshold = settings.usage.alertThreshold
        guard threshold > 0 else {
            usageThresholdMonitor = UsageThresholdMonitor(threshold: 0)
            return
        }
        usageThresholdMonitor.threshold = threshold

        let crossed = usageThresholdMonitor.crossings(in: currentUsageWindows())
        guard let worst = crossed.max(by: { $0.usedPercentage < $1.usedPercentage }) else { return }

        NotificationSoundService.play(.usageAlmostFull, settings: settings.sound)
        lastActionMessage = lang.t("island.usage.thresholdReached")
            .replacingOccurrences(of: "{window}", with: worst.label)
            .replacingOccurrences(of: "{value}", with: "\(Int(worst.usedPercentage.rounded()))")
    }

    func currentUsageWindows() -> [UsageThresholdMonitor.Window] {
        var windows: [UsageThresholdMonitor.Window] = []
        if let claude = claudeUsageSnapshot {
            if let fiveHour = claude.fiveHour {
                windows.append(.init(id: "claude", label: "5h", usedPercentage: fiveHour.usedPercentage, resetsAt: fiveHour.resetsAt))
            }
            if let sevenDay = claude.sevenDay {
                windows.append(.init(id: "claude", label: "7d", usedPercentage: sevenDay.usedPercentage, resetsAt: sevenDay.resetsAt))
            }
        }
        if let codex = codexUsageSnapshot {
            windows.append(contentsOf: codex.windows.map {
                .init(id: "codex", label: $0.label, usedPercentage: $0.usedPercentage, resetsAt: $0.resetsAt)
            })
        }
        return windows
    }

    var islandSurfaceAwaitsUserAction: Bool {
        guard let sessionID = islandSurface.sessionID,
              let session = state.session(id: sessionID) else {
            return false
        }
        return session.phase.requiresAttention
    }

    private func scheduleNotificationSurfacePresentationIfNeeded(
        _ surface: IslandSurface,
        wasAlreadyCompleted: Bool,
        ingress: TrackedEventIngress
    ) {
        guard !wasAlreadyCompleted,
              notificationSurfaceIsEligibleForPresentation(surface, ingress: ingress),
              let sessionID = surface.sessionID,
              let session = state.session(id: sessionID) else {
            return
        }

        guard suppressFrontmostNotifications else {
            presentNotificationSurface(surface)
            return
        }

        notificationPresentationTask?.cancel()
        notificationPresentationTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            let shouldSuppress = await self.isNotificationSessionAlreadyFrontmost(session)
            guard !Task.isCancelled,
                  !shouldSuppress,
                  self.notificationSurfaceIsEligibleForPresentation(surface, ingress: ingress) else {
                return
            }

            self.presentNotificationSurface(surface)
        }
    }

    private func notificationSurfaceIsEligibleForPresentation(
        _ surface: IslandSurface,
        ingress: TrackedEventIngress
    ) -> Bool {
        guard let sessionID = surface.sessionID,
              let session = state.session(id: sessionID) else {
            return false
        }

        return (ingress == .bridge || !isResolvingInitialLiveSessions)
            && (notchStatus == .closed || notchOpenReason == .notification)
            && !overlay.shouldPreserveCurrentNotificationSurface(against: surface)
            && surface.matchesCurrentState(of: session)
    }

    private func synchronizeSelection() {
        let surfacedIDs = Set(surfacedSessions.map(\.id))

        if let activeAction = state.activeActionableSession {
            selectedSessionID = activeAction.id
            return
        }

        guard let selectedSessionID,
              surfacedIDs.contains(selectedSessionID),
              state.session(id: selectedSessionID) != nil else {
            self.selectedSessionID = surfacedSessions.first?.id ?? state.sessions.first?.id
            return
        }
    }

    /// Applies startup discovery results on the main thread after background I/O completes.
    private func applyStartupDiscoveryPayload(_ payload: SessionDiscoveryCoordinator.StartupDiscoveryPayload) {
        discovery.applyStartupDiscoveryPayload(payload)

        // Apply hooks binary URL and update the installed copy if the app ships a newer version.
        hooks.hooksBinaryURL = payload.hooksBinaryURL
        hooks.updateHooksBinaryIfNeeded()

        // Auto-install missing hooks and usage bridge, then run health checks.
        if payload.hooksBinaryURL != nil {
            Task { @MainActor [weak self] in
                guard let self else { return }

                // Wait for all status reads to complete before checking install state.
                await self.hooks.refreshAllHookStatusAndWait()

                // Reconcile persisted intent with what is actually on disk. For
                // legacy users this records existing hooks as `.installed` and
                // marks first-launch as complete so onboarding does not appear
                // on upgrade. Must run after status reads and before any
                // install decision.
                self.hooks.migrateIntentStoreIfNeeded()

                // Install only hooks the user has not explicitly opted out of.
                // `shouldAutoInstall` skips `.uninstalled` agents and agents
                // whose hooks are already present — it is the single checkpoint
                // that fixes #324.
                if self.hooks.shouldAutoInstall(.claudeCode) { self.installClaudeHooks() }
                if self.hooks.shouldAutoInstall(.codex) { self.installCodexHooks() }
                if self.hooks.shouldAutoInstall(.qoder) { self.installQoderHooks() }
                if self.hooks.shouldAutoInstall(.qwenCode) { self.installQwenCodeHooks() }
                if self.hooks.shouldAutoInstall(.factory) { self.installFactoryHooks() }
                if self.hooks.shouldAutoInstall(.codebuddy) { self.installCodebuddyHooks() }
                if self.hooks.shouldAutoInstall(.openCode) { self.installOpenCodePlugin() }
                if self.hooks.shouldAutoInstall(.cursor) { self.installCursorHooks() }
                if self.hooks.shouldAutoInstall(.gemini) { self.installGeminiHooks() }
                if self.hooks.shouldAutoInstall(.kimi) { self.installKimiHooks() }
                if self.hooks.shouldAutoInstall(.claudeUsageBridge) { self.installClaudeUsageBridge() }

                // Run health checks after install to detect stale paths, conflicts, etc.
                try? await Task.sleep(for: .milliseconds(500))
                await self.hooks.repairHooksIfNeeded()
            }
        }

        // Reconcile attachments and start monitoring (requires sessions to be loaded).
        monitoring.reconcileSessionAttachments()
        monitoring.startMonitoringIfNeeded()
    }


    private var sessionBuckets: (primary: [AgentSession], restored: [AgentSession], overflow: [AgentSession]) {
        if let cached = _cachedSessionBuckets {
            return cached
        }
        let result = computeSessionBuckets()
        _cachedSessionBuckets = result
        return result
    }

    private func computeSessionBuckets() -> (primary: [AgentSession], restored: [AgentSession], overflow: [AgentSession]) {
        let now = Date.now
        // Silenced sessions drop out here rather than at the view, so they are
        // also absent from the counts, the notification surfaces and the sound.
        let visibleSessions = state.sessions.filter { !settings.notificationFilters.isSilenced($0) }
        let rankedSessions = visibleSessions.sorted { lhs, rhs in
            let lhsScore = displayPriority(for: lhs, now: now)
            let rhsScore = displayPriority(for: rhs, now: now)

            if lhsScore == rhsScore {
                if lhs.islandActivityDate == rhs.islandActivityDate {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }

                return lhs.islandActivityDate > rhs.islandActivityDate
            }

            return lhsScore > rhsScore
        }

        var primary: [AgentSession] = []
        var restored: [AgentSession] = []
        var claimedLiveAttachmentKeys: Set<String> = []

        // `isVisibleInIsland` requires a live process or a live hook session.
        // After a relaunch nothing satisfies that until `ps`/`lsof` discovery
        // finishes, so the panel sat empty for 20-30s on a machine with many
        // agent processes. Registry rows that were active inside the stale
        // window go to `restored`: the list shows them right away as idle,
        // while the live counters keep counting only what is actually live.
        // Bounded independently of `completedStaleThreshold`: that setting says
        // how long a *completed* row keeps full presentation, and "Never" would
        // otherwise surface every row in the 24h registry — 45 sessions on a
        // busy day. Restored-but-unconfirmed rows are only interesting while
        // the work is still fresh.
        let restoreGrace = min(completedStaleThreshold.seconds, Self.restoredSessionVisibilityWindow)
        for session in rankedSessions {
            guard !session.isSubagentSession else { continue }

            let isLive = session.isVisibleInIsland
            let isRecentlyActive = now.timeIntervalSince(session.islandActivityDate) < restoreGrace
            guard isLive || isRecentlyActive else { continue }

            if let liveAttachmentKey = monitoring.liveAttachmentKey(for: session) {
                guard claimedLiveAttachmentKeys.insert(liveAttachmentKey).inserted else {
                    continue
                }
            }

            if isLive {
                primary.append(session)
            } else {
                restored.append(session)
            }
        }

        let shownIDs = Set((primary + restored).map(\.id))
        let overflow = rankedSessions.filter { !shownIDs.contains($0.id) && !$0.isSubagentSession }
        return (primary, restored, overflow)
    }

    private func displayPriority(for session: AgentSession, now: Date) -> Int {
        var score = 0

        let presence = session.islandPresence(at: now)

        if session.isProcessAlive {
            score += presence == .inactive ? 3_000 : 12_000
        } else if session.isDemoSession || session.phase.requiresAttention {
            score += 6_000
        }

        if session.phase.requiresAttention {
            score += 10_000
        }

        if session.currentToolName?.isEmpty == false {
            score += 6_000
        }

        if session.jumpTarget != nil {
            score += 4_000
        }

        switch session.phase {
        case .running:
            score += 2_000
        case .waitingForApproval:
            score += 1_500
        case .waitingForAnswer:
            score += 1_200
        case .completed:
            score += 600
        }

        if session.isStaleCompletedForIsland(at: now, threshold: completedStaleThreshold.seconds) {
            score -= 900
        }

        let age = now.timeIntervalSince(session.islandActivityDate)
        switch age {
        case ..<120:
            score += 500
        case ..<900:
            score += 250
        case ..<3_600:
            score += 120
        case ..<21_600:
            score += 40
        default:
            break
        }

        return score
    }

    private func describe(_ event: AgentEvent) -> String {
        switch event {
        case let .sessionStarted(payload):
            return "Session started: \(payload.title)"
        case let .activityUpdated(payload):
            return payload.summary
        case let .permissionRequested(payload):
            return payload.request.summary
        case let .questionAsked(payload):
            return payload.prompt.title
        case let .sessionCompleted(payload):
            return payload.summary
        case let .jumpTargetUpdated(payload):
            return "Jump target updated to \(payload.jumpTarget.terminalApp)."
        case let .sessionMetadataUpdated(payload):
            if let currentTool = payload.codexMetadata.currentTool {
                return "Codex is running \(currentTool)."
            }

            return payload.codexMetadata.lastAssistantMessage ?? "Codex session metadata updated."
        case let .claudeSessionMetadataUpdated(payload):
            if let currentTool = payload.claudeMetadata.currentTool {
                return "Claude is running \(currentTool)."
            }

            return payload.claudeMetadata.lastAssistantMessage ?? "Claude session metadata updated."
        case let .geminiSessionMetadataUpdated(payload):
            return payload.geminiMetadata.lastAssistantMessage ?? "Gemini session metadata updated."
        case let .openCodeSessionMetadataUpdated(payload):
            if let currentTool = payload.openCodeMetadata.currentTool {
                return "OpenCode is running \(currentTool)."
            }

            return payload.openCodeMetadata.lastAssistantMessage ?? "OpenCode session metadata updated."
        case let .cursorSessionMetadataUpdated(payload):
            if let currentTool = payload.cursorMetadata.currentTool {
                return "Cursor is running \(currentTool)."
            }

            return payload.cursorMetadata.lastAssistantMessage ?? "Cursor session metadata updated."
        case let .actionableStateResolved(payload):
            return "Actionable state resolved for session \(payload.sessionID)."
        }
    }

    func quitApplication() {
        NSApplication.shared.terminate(nil)
    }

}

// MARK: - Hex color helpers

extension String {
    var normalizedHexColorString: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard raw.count == 6, raw.allSatisfy(\.isHexDigit) else { return "#6E9FFF" }
        return "#\(raw.uppercased())"
    }
}

extension Color {
    init?(hex: String) {
        let raw = String(hex.normalizedHexColorString.dropFirst())
        guard let value = Int(raw, radix: 16) else { return nil }
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self = Color(red: red, green: green, blue: blue)
    }

    var opaqueHexString: String? {
        guard let nsColor = NSColor(self).usingColorSpace(.deviceRGB) else { return nil }
        let r = Int(round(nsColor.redComponent * 255))
        let g = Int(round(nsColor.greenComponent * 255))
        let b = Int(round(nsColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
