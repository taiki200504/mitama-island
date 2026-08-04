import SwiftUI
@preconcurrency import MarkdownUI
import OpenIslandCore

private struct NotificationContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Auto-height container: renders content directly (auto-sizing).
/// When content exceeds maxHeight, wraps in ScrollView at fixed maxHeight.
private struct AutoHeightScrollView<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: () -> Content
    @State private var contentHeight: CGFloat = 0

    private var isScrollable: Bool { contentHeight > maxHeight }

    var body: some View {
        // Always use ScrollView so the content gets unconstrained vertical
        // space for measurement.  Without this, a tight parent window can
        // cap the GeometryReader measurement, making long content appear
        // truncated instead of scrollable.
        ScrollView(.vertical) {
            content()
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                    }
                )
                .onPreferenceChange(ContentHeightKey.self) { height in
                    if height > 0 { contentHeight = height }
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(isScrollable ? .automatic : .hidden)
        .frame(height: contentHeight > 0 ? min(contentHeight, maxHeight) : nil)
    }
}

// MARK: - Row Height Estimation

extension AgentSession {
    /// Estimated row height matching `IslandSessionRow` layout for viewport sizing.
    func estimatedIslandRowHeight(
        at date: Date,
        fields: IslandSessionCardFields = .all
    ) -> CGFloat {
        let presence = islandPresence(at: date)
        // v8 list rows are full-width scan rows, not rounded cards.
        // Base: vertical padding (22) + headline (~17) + divider rounding.
        var height: CGFloat = 40
        guard presence != .inactive else { return height }
        if spotlightPromptLineText != nil { height += 17 }
        if fields.showsAgentActivity, spotlightActivityLineText != nil { height += 20 }
        if fields.showsSubagents,
           let subagents = claudeMetadata?.activeSubagents, !subagents.isEmpty {
            height += 18
            height += CGFloat(subagents.count) * 18  // each subagent row (spacing 4 + text 14)
        }
        if fields.showsTasks,
           let tasks = claudeMetadata?.activeTasks, !tasks.isEmpty {
            height += 17
            height += CGFloat(tasks.count) * 16  // each task row (spacing 3 + text 13)
        }
        return height
    }
}

/// Which optional facts a session row is allowed to carry.
///
/// Defaults to showing everything, so a caller that does not care — a preview, a
/// test, the notification card — keeps the behaviour the row always had.
struct IslandSessionCardFields: Equatable, Sendable {
    var showsTasks: Bool = true
    var showsSubagents: Bool = true
    var showsAgentActivity: Bool = true
    var showsProjectName: Bool = false
    var showsWorktree: Bool = false
    var showsModel: Bool = false

    static let all = IslandSessionCardFields()

    init(
        showsTasks: Bool = true,
        showsSubagents: Bool = true,
        showsAgentActivity: Bool = true,
        showsProjectName: Bool = false,
        showsWorktree: Bool = false,
        showsModel: Bool = false
    ) {
        self.showsTasks = showsTasks
        self.showsSubagents = showsSubagents
        self.showsAgentActivity = showsAgentActivity
        self.showsProjectName = showsProjectName
        self.showsWorktree = showsWorktree
        self.showsModel = showsModel
    }

    @MainActor
    init(display: DisplaySettings) {
        self.init(
            showsTasks: display.showTasks,
            showsSubagents: display.showSubagents,
            showsAgentActivity: display.showAgentActivity,
            showsProjectName: display.showProjectName,
            showsWorktree: display.showWorktree,
            showsModel: display.showModel
        )
    }
}

// MARK: - Animations

// Timings measured off a 120fps capture of the reference product: the panel
// grows for ~225ms with a decelerating curve and no overshoot, and collapses
// in ~150ms. The previous 0.42s response felt soft and lagged the pointer;
// 0.3s response at high damping lands on the same wall-clock duration.
private let openAnimation = Animation.spring(response: 0.3, dampingFraction: 0.9, blendDuration: 0)
private let closeAnimation = Animation.smooth(duration: 0.15)
private let popAnimation = Animation.spring(response: 0.3, dampingFraction: 0.5)
// Slightly longer than `closeAnimation` so the collapse is never cut off
// mid-shrink by the surface being torn down.
private let openedSurfaceUnmountDelay: TimeInterval = 0.22

private struct ConditionalDrawingGroup: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.drawingGroup()
        } else {
            content
        }
    }
}

// MARK: - Main island view

struct IslandPanelView: View {
    private static let headerControlButtonSize: CGFloat = 22
    private static let headerControlSpacing: CGFloat = 8
    private static let headerHorizontalPadding: CGFloat = 18
    private static let headerTopPadding: CGFloat = 2
    private static let notchHeaderHorizontalPadding: CGFloat = 46
    private static let notchLaneSafetyInset: CGFloat = 12
    private static let minimumRightUsageLaneWidth: CGFloat = 58

    var model: AppModel
    private var lang: LanguageManager { model.lang }

    @State private var isHovering = false
    @State private var showingQuitConfirmation = false
    @State private var keepsOpenedSurfaceMounted = false
    @State private var openedSurfaceMountGeneration: UInt64 = 0

    private var isOpened: Bool {
        model.notchStatus == .opened
    }

    private var usesOpenedVisualState: Bool {
        isOpened
    }

    private var shouldRenderOpenedSurface: Bool {
        usesOpenedVisualState || keepsOpenedSurfaceMounted
    }

    private var isPopping: Bool {
        model.notchStatus == .popping
    }

    /// Single animation selection based on the current notch status.
    private var notchTransitionAnimation: Animation {
        switch model.notchStatus {
        case .opened:  return openAnimation
        case .closed:  return closeAnimation
        case .popping: return popAnimation
        }
    }

    private var targetOverlayScreen: NSScreen? {
        if let targetScreenID = model.overlayPlacementDiagnostics?.targetScreenID,
           let screen = NSScreen.screens.first(where: { OverlayDisplayResolver.screenID(for: $0) == targetScreenID }) {
            return screen
        }

        return NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    private var usesNotchAwareOpenedHeader: Bool {
        model.overlayPlacementDiagnostics?.mode == .notch
            || targetOverlayScreen?.safeAreaInsets.top ?? 0 > 0
    }

    /// True when the closed island sits on an external (non-notched) display.
    /// The central black rectangle is otherwise aligned with the physical
    /// notch, so center content is only useful here.
    private var isExternalDisplayPlacement: Bool {
        if let mode = model.overlayPlacementDiagnostics?.mode {
            return mode == .topBar
        }
        // Fallback when diagnostics haven't been populated yet.
        return (targetOverlayScreen?.safeAreaInsets.top ?? 0) == 0
    }

    private var openedHeaderButtonsWidth: CGFloat {
        (Self.headerControlButtonSize * 3) + (Self.headerControlSpacing * 2)
    }

    private var openedHeaderHorizontalPadding: CGFloat {
        usesNotchAwareOpenedHeader ? Self.notchHeaderHorizontalPadding : Self.headerHorizontalPadding
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color.clear

                notchContent(availableSize: geometry.size)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .alert(model.lang.t("island.quit.confirmTitle"), isPresented: $showingQuitConfirmation) {
            Button(model.lang.t("island.quit.confirmAction"), role: .destructive) {
                model.quitApplication()
            }
            Button(model.lang.t("settings.general.cancel"), role: .cancel) {}
        } message: {
            Text(model.lang.t("island.quit.confirmMessage"))
        }
        .onAppear {
            syncOpenedSurfaceMount(with: model.notchStatus, immediate: true)
        }
        .onChange(of: model.notchStatus) { _, status in
            syncOpenedSurfaceMount(with: status)
        }
    }

    @ViewBuilder
    private func notchContent(availableSize: CGSize) -> some View {
        // Window is always at opened size — use opened insets unconditionally.
        let panelShadowHorizontalInset = IslandChromeMetrics.openedShadowHorizontalInset
        let panelShadowBottomInset = IslandChromeMetrics.openedShadowBottomInset
        let layoutWidth = max(0, availableSize.width - (panelShadowHorizontalInset * 2))
        let layoutHeight = max(0, availableSize.height - panelShadowBottomInset)

        let outerHorizontalPadding: CGFloat = 0
        let outerBottomPadding: CGFloat = 0
        let openedWidth = max(0, layoutWidth - outerHorizontalPadding)
        let openedHeight = max(closedNotchHeight, layoutHeight - outerBottomPadding)

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                if shouldRenderOpenedSurface {
                    openedSurface(width: openedWidth, height: openedHeight)
                        .opacity(usesOpenedVisualState ? 1 : 0)
                        .allowsHitTesting(usesOpenedVisualState)
                }

                v6ClosedSurface()
                    .opacity(usesOpenedVisualState ? 0 : 1)
                    .allowsHitTesting(!usesOpenedVisualState)
                    // The pill sits against the physical notch, so it cannot
                    // grow a border to answer the cursor — a glow is the only
                    // edge it has room for.
                    .shadow(
                        color: isHovering && !usesOpenedVisualState
                            ? IslandThemes.current.accent.opacity(0.55)
                            : .clear,
                        radius: IslandThemes.current.glowRadius * 3
                    )
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scaleEffect(usesOpenedVisualState ? 1 : (isHovering ? IslandChromeMetrics.closedHoverScale : 1), anchor: .top)
        .padding(.horizontal, panelShadowHorizontalInset)
        .padding(.bottom, panelShadowBottomInset)
        .animation(notchTransitionAnimation, value: model.notchStatus)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            if model.notchStatus != .opened {
                model.notchOpen(reason: .click)
            }
        }
    }

    private func syncOpenedSurfaceMount(with status: NotchStatus, immediate: Bool = false) {
        openedSurfaceMountGeneration &+= 1
        let generation = openedSurfaceMountGeneration

        switch status {
        case .opened:
            keepsOpenedSurfaceMounted = true
        case .closed, .popping:
            guard !immediate else {
                keepsOpenedSurfaceMounted = false
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + openedSurfaceUnmountDelay) {
                guard openedSurfaceMountGeneration == generation,
                      model.notchStatus != .opened else {
                    return
                }
                keepsOpenedSurfaceMounted = false
            }
        }
    }

    // MARK: - v6 closed surface

    /// Closed island per v6 spec. Renders the flat-top pill with the
    /// UnifiedBars glyph, respecting the user's right-slot / center-label
    /// preferences. AppModel is @Observable so any change to sessions /
    /// preferences re-renders this automatically; UnifiedBars runs its own
    /// TimelineView internally for bar animation.
    @ViewBuilder
    private func v6ClosedSurface() -> some View {
        let layout: V6ClosedLayout = isExternalDisplayPlacement ? .external : .macbook
        let physicalNotchWidth: CGFloat = targetOverlayScreen?.notchSize.width ?? 180
        V6ClosedPill(
            mode: model.islandClosedMode,
            label: layout == .external ? model.islandClosedLabel() : nil,
            rightSlot: model.islandClosedRightSlotContent(),
            layout: layout,
            height: closedNotchHeight,
            physicalNotchWidth: layout == .macbook ? physicalNotchWidth : 0,
            minWidth: 70
        )
        .scaleEffect(isPopping ? 1.04 : 1, anchor: .top)
        .animation(popAnimation, value: isPopping)
    }

    // MARK: - Opened surface

    @ViewBuilder
    private func openedSurface(width openedWidth: CGFloat, height openedHeight: CGFloat) -> some View {
        let horizontalInset = 0.0
        let bottomInset = 0.0
        let surfaceWidth = openedWidth + (horizontalInset * 2)
        let surfaceHeight = openedHeight + bottomInset
        let surfaceShape = OpenedIslandSurfaceShape(
            topProfile: usesNotchAwareOpenedHeader ? .notch : .topBar
        )

        ZStack(alignment: .top) {
            surfaceShape
                .fill(V6Palette.ink)
                .frame(width: surfaceWidth, height: surfaceHeight)

            VStack(spacing: 0) {
                openedHeaderContent
                    .frame(height: closedNotchHeight)

                openedContent
                    .frame(width: openedWidth)
                    .frame(maxHeight: max(0, openedHeight - closedNotchHeight), alignment: .top)
                    .clipped()
            }
            .frame(width: openedWidth, height: openedHeight, alignment: .top)
            .padding(.horizontal, horizontalInset)
            .padding(.bottom, bottomInset)
            .clipShape(surfaceShape)
            .overlay {
                surfaceShape
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            }
        }
        .frame(width: surfaceWidth, height: surfaceHeight, alignment: .top)
    }

    // MARK: - Closed state

    private var closedNotchWidth: CGFloat {
        (targetOverlayScreen ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }))?.notchSize.width ?? NSScreen.externalDisplayNotchWidth
    }

    private var closedNotchHeight: CGFloat {
        (targetOverlayScreen ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }))?.islandClosedHeight ?? 24
    }

    @ViewBuilder
    private var openedHeaderContent: some View {
        if usesNotchAwareOpenedHeader {
            GeometryReader { geometry in
                let providers = openedUsageProviders
                let providerGroups = splitUsageProviders(providers)
                let metrics = openedHeaderMetrics(for: geometry.size.width)

                HStack(spacing: 0) {
                    usageLaneView(providerGroups.left, alignment: .leading)
                        .frame(width: metrics.leftUsageWidth, alignment: .leading)

                    Color.clear
                        .frame(width: metrics.centerGapWidth)

                    HStack(spacing: Self.headerControlSpacing) {
                        if metrics.rightUsageWidth > 0, !providerGroups.right.isEmpty {
                            usageLaneView(providerGroups.right, alignment: .trailing)
                                .frame(width: metrics.rightUsageWidth, alignment: .trailing)
                        }
                        openedHeaderButtons
                    }
                    .frame(width: metrics.rightLaneWidth, alignment: .trailing)
                }
                .padding(.horizontal, openedHeaderHorizontalPadding)
                .padding(.top, Self.headerTopPadding)
            }
        } else {
            HStack(spacing: 12) {
                openedUsageSummary
                    .frame(maxWidth: .infinity, alignment: .leading)

                openedHeaderButtons
            }
            .padding(.leading, openedHeaderHorizontalPadding)
            .padding(.trailing, openedHeaderHorizontalPadding)
            .padding(.top, Self.headerTopPadding)
        }
    }

    private var openedHeaderButtons: some View {
        HStack(spacing: Self.headerControlSpacing) {
            headerIconButton(
                systemName: model.isSoundMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                tint: model.isSoundMuted ? .orange.opacity(0.92) : .white.opacity(0.62)
            ) {
                model.toggleSoundMuted()
            }

            headerIconButton(systemName: "gearshape.fill", tint: .white.opacity(0.62)) {
                model.showSettings()
            }

            headerIconButton(
                systemName: "power",
                tint: .white.opacity(0.62),
                accessibilityLabel: model.lang.t("island.quit.confirmTitle")
            ) {
                showingQuitConfirmation = true
            }
        }
    }

    private func headerIconButton(
        systemName: String,
        tint: Color,
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.islandText(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: Self.headerControlButtonSize, height: Self.headerControlButtonSize)
                .background(.white.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? systemName)
    }

    private var openedContent: some View {
        VStack(spacing: 8) {
            if !model.hasAnyInstalledAgent {
                installHooksHint
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
            }

            if model.shouldShowSessionBootstrapPlaceholder {
                sessionBootstrapPlaceholder
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
            } else if model.islandListSessions.isEmpty {
                emptyState
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
            } else {
                sessionList
            }
        }
        .padding(.bottom, 0)
    }

    /// Persistent hint at the top of the expanded island while no agent
    /// hooks are installed. Decoupled from session presence — process
    /// discovery routinely surfaces sessions even on a freshly cleaned
    /// install, so the empty-state branch alone never reaches users who
    /// already run an agent.
    private var installHooksHint: some View {
        Button {
            model.showOnboarding()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.islandText(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(model.lang.t("island.hint.installHooks"))
                    .font(.islandText(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.islandText(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                IslandThemes.current.shape(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.14))
                    .overlay(
                        IslandThemes.current.shape(cornerRadius: 10)
                            .stroke(Color.accentColor.opacity(0.35), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var sessionBootstrapPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white.opacity(0.7))
                .scaleEffect(0.8)
            Text(model.lang.t("island.checkingTerminals"))
                .font(.islandText(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
            Text(model.lang.t("island.terminalOwnership"))
                .font(.islandText(size: 12))
                .foregroundStyle(.white.opacity(0.28))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(model.lang.t("island.noTerminals"))
                .font(.islandText(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
            Text(model.recentSessions.isEmpty
                ? model.lang.t("island.startAgent")
                : model.lang.t("island.recentSessions"))
                .font(.islandText(size: 12))
                .foregroundStyle(.white.opacity(0.25))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var actionableSessionID: String? {
        model.islandSurface.sessionID
    }

    /// Whether the panel was opened by a notification (show only actionable session + footer).
    private var isNotificationMode: Bool {
        model.notchOpenReason == .notification && actionableSessionID != nil
    }

    private var maxSessionListHeight: CGFloat {
        model.settings.display.maxPanelHeight
    }

    private var cardFields: IslandSessionCardFields {
        IslandSessionCardFields(display: model.settings.display)
    }

    private var sessionListSideInset: CGFloat {
        usesNotchAwareOpenedHeader ? 46 : 16
    }

    private var sessionList: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let referenceDate = context.date

            if isNotificationMode {
                // Notification mode: NO ScrollView — content sizes naturally
                sessionListContent(referenceDate: referenceDate)
                    .padding(.vertical, 2)
                    .onHover { hovering in
                        if hovering {
                            model.notePointerInsideIslandSurface()
                        } else {
                            model.handlePointerExitedIslandSurface()
                        }
                    }
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: NotificationContentHeightKey.self,
                                value: geo.size.height
                            )
                        }
                    )
                    .onPreferenceChange(NotificationContentHeightKey.self) { height in
                        if height > 0 {
                            model.measuredNotificationContentHeight = height
                        }
                    }
            } else {
                VStack(spacing: 0) {
                    sessionPanelHeader(referenceDate: referenceDate)

                    ScrollView(.vertical) {
                        sessionRowsContent(referenceDate: referenceDate)
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)

                    sessionPanelFooter
                }
                .padding(.vertical, 2)
            }
        }
    }

    /// mitama's own queue, above the agent sessions. Agents answer "what is
    /// running"; this answers "what is waiting on me", and that question
    /// outranks the first one.
    @ViewBuilder
    private var mitamaFeedSection: some View {
        let notifications = model.mitamaFeed.notifications
        if model.mitamaFeedEnabled, !notifications.isEmpty {
            VStack(spacing: 0) {
                ForEach(notifications) { notification in
                    Button {
                        model.openMitamaHub()
                        model.mitamaFeed.markRead(notification)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(mitamaTint(for: notification.level))
                                .frame(width: 7, height: 7)
                                .padding(.top, 4)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(notification.title)
                                    .font(.islandText(size: 12.5, weight: .semibold))
                                    .foregroundStyle(V6Palette.paper.opacity(0.92))
                                    .lineLimit(1)

                                if !notification.body.isEmpty {
                                    Text(notification.body)
                                        .font(.islandText(size: 11, weight: .medium))
                                        .foregroundStyle(V6Palette.paper.opacity(0.5))
                                        .lineLimit(1)
                                }
                            }

                            Spacer(minLength: 8)

                            Text(model.lang.t("mitama.level.\(notification.level.rawValue)"))
                                .font(.islandText(size: 10, weight: .semibold))
                                .foregroundStyle(mitamaTint(for: notification.level))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(mitamaTint(for: notification.level).opacity(0.14), in: Capsule())
                        }
                        .padding(.horizontal, sessionListSideInset)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(.white.opacity(0.06))
                    .frame(height: 1)
            }
        }
    }

    private func mitamaTint(for level: MitamaNotification.Level) -> Color {
        switch level {
        case .urgent:
            return IslandDesignPalette.Status.waitingForApproval
        case .homework:
            return IslandDesignPalette.Status.waitingForAnswer
        case .digest, .info:
            return IslandDesignPalette.Status.idle
        }
    }

    @ViewBuilder
    private func sessionListContent(referenceDate: Date) -> some View {
        VStack(spacing: 0) {
            if !isNotificationMode {
                mitamaFeedSection
                sessionPanelHeader(referenceDate: referenceDate)
            }

            if isNotificationMode, let session = model.activeIslandCardSession {
                IslandSessionRow(
                    session: session,
                    referenceDate: referenceDate,
                    stateIndicator: model.islandSessionStateIndicator,
                    completedStaleThreshold: model.completedStaleThreshold.seconds,
                    isActionable: true,
                    useDrawingGroup: model.notchStatus == .opened,
                    isInteractive: model.notchStatus == .opened,
                    presentation: .notification,
                    sideInset: sessionListSideInset,
                    cardFields: cardFields,
                    lang: model.lang,
                    onApprove: { model.approvePermission(for: session.id, action: $0) },
                    onResolveAll: { model.resolveAllPendingApprovals($0) },
                    pendingApprovalCount: model.pendingApprovalSessions.count,
                    onAnswer: { model.answerQuestion(for: session.id, answer: $0) },
                    onReply: TerminalTextSender.canReply(to: session, enabled: model.completionReplyEnabled)
                        ? { model.replyToSession(session, text: $0) } : nil,
                    onJump: { model.jumpToSession(session) },
                    onHide: { model.hideSessions(matching: $0) },
                    agentIconStyle: model.agentIconStyle,
                    shortcutHint: model.shortcutHints.isModifierHeld ? model.settings.shortcuts : nil,
                    isSwitcherHighlighted: model.switcher.highlightedID == session.id,
                    usesAutoNaming: model.settings.display.sessionAutoNaming
                )
                .id(notificationCardIdentity(for: session))

                if model.allSessions.count > 1 {
                    Button {
                        let isCompletion = session.phase == .completed
                        model.expandNotificationToSessionList(clearExpansion: isCompletion)
                    } label: {
                        Text(model.lang.t("island.showAll", model.allSessions.count))
                            .font(.islandText(size: 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.36))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, sessionListSideInset)
                            .padding(.top, 6)
                            .padding(.bottom, 2)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ForEach(model.islandSessionSections) { section in
                    VStack(alignment: .leading, spacing: 0) {
                        if model.islandSessionGroup != .none {
                            sessionSectionHeader(section)
                        }

                        ForEach(section.sessions) { session in
                            IslandSessionRow(
                                session: session,
                                referenceDate: referenceDate,
                                stateIndicator: model.islandSessionStateIndicator,
                                completedStaleThreshold: model.completedStaleThreshold.seconds,
                                isActionable: session.phase.requiresAttention || session.id == actionableSessionID,
                                useDrawingGroup: model.notchStatus == .opened,
                                isInteractive: model.notchStatus == .opened,
                                sideInset: sessionListSideInset,
                                cardFields: cardFields,
                                lang: model.lang,
                                onApprove: { model.approvePermission(for: session.id, action: $0) },
                                onResolveAll: { model.resolveAllPendingApprovals($0) },
                                pendingApprovalCount: model.pendingApprovalSessions.count,
                                onAnswer: { model.answerQuestion(for: session.id, answer: $0) },
                                onReply: TerminalTextSender.canReply(to: session, enabled: model.completionReplyEnabled)
                                    ? { model.replyToSession(session, text: $0) } : nil,
                                onJump: { model.jumpToSession(session) },
                                onDismiss: session.isRemote ? { model.dismissSession(session.id) } : nil,
                                onHide: { model.hideSessions(matching: $0) },
                    agentIconStyle: model.agentIconStyle,
                    shortcutHint: model.shortcutHints.isModifierHeld ? model.settings.shortcuts : nil,
                    isSwitcherHighlighted: model.switcher.highlightedID == session.id,
                    usesAutoNaming: model.settings.display.sessionAutoNaming
                            )
                        }
                    }
                }
            }

            if !isNotificationMode {
                sessionPanelFooter
            }
        }
    }

    private func notificationCardIdentity(for session: AgentSession) -> String {
        switch session.phase {
        case .waitingForApproval:
            return "\(session.id)|approval|\(session.permissionRequest?.id.uuidString ?? "none")"
        case .waitingForAnswer:
            return "\(session.id)|question|\(session.questionPrompt?.id.uuidString ?? "none")"
        case .completed:
            return "\(session.id)|completed|\(session.updatedAt.timeIntervalSinceReferenceDate)"
        case .running:
            return "\(session.id)|running"
        }
    }

    @ViewBuilder
    private func sessionRowsContent(referenceDate: Date) -> some View {
        ForEach(model.islandSessionSections) { section in
            VStack(alignment: .leading, spacing: 0) {
                if model.islandSessionGroup != .none {
                    sessionSectionHeader(section)
                }

                ForEach(section.sessions) { session in
                    IslandSessionRow(
                        session: session,
                        referenceDate: referenceDate,
                        stateIndicator: model.islandSessionStateIndicator,
                        completedStaleThreshold: model.completedStaleThreshold.seconds,
                        isActionable: session.phase.requiresAttention || session.id == actionableSessionID,
                        useDrawingGroup: model.notchStatus == .opened,
                        isInteractive: model.notchStatus == .opened,
                        sideInset: sessionListSideInset,
                        cardFields: cardFields,
                        lang: model.lang,
                        onApprove: { model.approvePermission(for: session.id, action: $0) },
                        onResolveAll: { model.resolveAllPendingApprovals($0) },
                        pendingApprovalCount: model.pendingApprovalSessions.count,
                        onAnswer: { model.answerQuestion(for: session.id, answer: $0) },
                        onReply: TerminalTextSender.canReply(to: session, enabled: model.completionReplyEnabled)
                            ? { model.replyToSession(session, text: $0) } : nil,
                        onJump: { model.jumpToSession(session) },
                        onDismiss: session.isRemote ? { model.dismissSession(session.id) } : nil,
                        onHide: { model.hideSessions(matching: $0) },
                    agentIconStyle: model.agentIconStyle,
                    shortcutHint: model.shortcutHints.isModifierHeld ? model.settings.shortcuts : nil,
                    isSwitcherHighlighted: model.switcher.highlightedID == session.id,
                    usesAutoNaming: model.settings.display.sessionAutoNaming
                    )
                }
            }
        }
    }

    /// The list needs no "SESSIONS" label — the panel contains nothing else,
    /// and the 36pt it occupied cost a visible row on a 6-row list. The state
    /// counts stay, left-aligned where the label used to be.
    private func sessionPanelHeader(referenceDate: Date) -> some View {
        let overview = sessionOverviewItems(referenceDate: referenceDate)

        return HStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                sessionOverviewView(overview, compact: false)
                sessionOverviewView(overview, compact: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, sessionListSideInset)
        .padding(.trailing, sessionListSideInset)
        .frame(height: 24)
    }

    private var sessionPanelFooter: some View {
        Color.clear
            .frame(height: 10)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.055))
                .frame(height: 1)
        }
    }

    private func sessionOverviewItems(referenceDate: Date) -> [SessionOverviewItem] {
        let sessions = model.islandListSessions
        guard !sessions.isEmpty else { return [] }

        let threshold = model.completedStaleThreshold.seconds
        let waiting = sessions.filter(\.phase.requiresAttention).count
        let running = sessions.filter { $0.phase == .running }.count
        let done = sessions.filter {
            $0.phase == .completed
                && !isIdleSessionOverviewItem($0, referenceDate: referenceDate, threshold: threshold)
        }.count
        let idle = sessions.filter {
            isIdleSessionOverviewItem($0, referenceDate: referenceDate, threshold: threshold)
        }.count

        return [
            SessionOverviewItem(id: "total", title: lang.t("island.sessionOverview.total"), compactTitle: "", count: sessions.count, tint: nil),
            SessionOverviewItem(id: "waiting", title: lang.t("island.sessionOverview.waiting"), compactTitle: lang.t("island.sessionOverview.waitingCompact"), count: waiting, tint: IslandDesignPalette.Status.waitingAggregate),
            SessionOverviewItem(id: "running", title: lang.t("island.sessionOverview.running"), compactTitle: lang.t("island.sessionOverview.runningCompact"), count: running, tint: IslandDesignPalette.Status.running),
            SessionOverviewItem(id: "done", title: lang.t("island.sessionOverview.done"), compactTitle: lang.t("island.sessionOverview.done"), count: done, tint: IslandDesignPalette.Status.completed),
            SessionOverviewItem(id: "idle", title: lang.t("island.sessionOverview.idle"), compactTitle: lang.t("island.sessionOverview.idle"), count: idle, tint: IslandDesignPalette.Status.idle),
        ].filter { $0.id == "total" || $0.count > 0 }
    }

    private func isIdleSessionOverviewItem(
        _ session: AgentSession,
        referenceDate: Date,
        threshold: TimeInterval
    ) -> Bool {
        guard session.phase == .completed else { return false }
        return session.isStaleCompletedForIsland(at: referenceDate, threshold: threshold)
            || session.islandPresence(at: referenceDate) == .inactive
    }

    private func sessionOverviewView(_ items: [SessionOverviewItem], compact: Bool) -> some View {
        HStack(spacing: compact ? 7 : 9) {
            ForEach(items) { item in
                sessionOverviewMetric(item, compact: compact)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func sessionOverviewMetric(_ item: SessionOverviewItem, compact: Bool) -> some View {
        HStack(spacing: 4) {
            if let tint = item.tint {
                Circle()
                    .fill(tint)
                    .frame(width: 5.5, height: 5.5)
            }

            Text(sessionOverviewMetricTitle(item, compact: compact))
                .font(.islandMono(size: 10.5, weight: .semibold))
                .foregroundStyle(item.tint == nil ? V6Palette.paper.opacity(0.34) : V6Palette.paper.opacity(0.48))
        }
    }

    private func sessionOverviewMetricTitle(_ item: SessionOverviewItem, compact: Bool) -> String {
        if item.id == "total" {
            return compact ? "\(item.count)" : "\(item.count) \(item.title)"
        }

        return "\(item.count) \(compact ? item.compactTitle : item.title)"
    }

    private func sessionSectionHeader(_ section: IslandSessionSection) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(sectionTint(for: section))
                .frame(width: 7, height: 7)
            Text(sessionSectionTitle(for: section).uppercased())
                .font(.islandMono(size: 10.5, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(sectionLabelColor(for: section))
            Text("\(section.sessions.count)")
                .font(.islandMono(size: 10.5, weight: .medium))
                .foregroundStyle(V6Palette.paper.opacity(0.4))
            Spacer(minLength: 0)
        }
        .padding(.leading, sessionListSideInset)
        .padding(.trailing, sessionListSideInset)
        .padding(.top, 10)
        .padding(.bottom, 7)
        .background(Color.white.opacity(0.008))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.055))
                .frame(height: 1)
        }
    }

    private func sectionTint(for section: IslandSessionSection) -> Color {
        guard let first = section.sessions.first else { return IslandDesignPalette.Status.idle }
        if section.id == "state-idle" { return IslandDesignPalette.Status.idle }
        return IslandDesignPalette.Status.tint(for: first.phase)
    }

    private func sessionSectionTitle(for section: IslandSessionSection) -> String {
        if section.title.hasPrefix("island.") {
            return lang.t(section.title)
        }
        return section.title
    }

    private func sectionLabelColor(for section: IslandSessionSection) -> Color {
        switch section.id {
        case "state-approval":
            return IslandDesignPalette.Status.waitingForApproval.opacity(0.86)
        case "state-answer":
            return IslandDesignPalette.Status.waitingForAnswer.opacity(0.86)
        default:
            return V6Palette.paper.opacity(0.7)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private var openedUsageSummary: some View {
        let providers = openedUsageProviders

        if providers.isEmpty == false {
            ViewThatFits(in: .horizontal) {
                compactUsageSummaryView(providers, usesShortTitles: false)
                compactUsageSummaryView(providers, usesShortTitles: true)
            }
        } else {
            Color.clear
        }
    }

    private var openedUsageProviders: [UsageProviderPresentation] {
        guard model.islandUsageDisplay == .compact else {
            return []
        }

        var providers: [UsageProviderPresentation] = []

        if let snapshot = model.claudeUsageSnapshot,
           snapshot.isEmpty == false {
            var windows: [UsageWindowPresentation] = []

            if let fiveHour = snapshot.fiveHour {
                windows.append(
                    UsageWindowPresentation(
                        id: "claude-5h",
                        label: "5h",
                        usedPercentage: fiveHour.usedPercentage,
                        resetsAt: fiveHour.resetsAt
                    )
                )
            }

            if let sevenDay = snapshot.sevenDay {
                windows.append(
                    UsageWindowPresentation(
                        id: "claude-7d",
                        label: "7d",
                        usedPercentage: sevenDay.usedPercentage,
                        resetsAt: sevenDay.resetsAt
                    )
                )
            }

            if windows.isEmpty == false {
                providers.append(
                    UsageProviderPresentation(
                        id: "claude",
                        title: "Claude",
                        windows: windows
                    )
                )
            }
        }

        if model.showCodexUsage,
           let snapshot = model.codexUsageSnapshot,
           snapshot.isEmpty == false {
            let windows = snapshot.windows.map { window in
                UsageWindowPresentation(
                    id: "codex-\(window.key)",
                    label: window.label,
                    usedPercentage: window.usedPercentage,
                    resetsAt: window.resetsAt
                )
            }

            if windows.isEmpty == false {
                providers.append(
                    UsageProviderPresentation(
                        id: "codex",
                        title: "Codex",
                        windows: windows
                    )
                )
            }
        }

        return providers
    }

    private func splitUsageProviders(
        _ providers: [UsageProviderPresentation]
    ) -> (left: [UsageProviderPresentation], right: [UsageProviderPresentation]) {
        switch providers.count {
        case 0:
            return ([], [])
        case 1:
            return ([providers[0]], [])
        case 2:
            return ([providers[0]], [providers[1]])
        default:
            let splitIndex = Int(ceil(Double(providers.count) / 2.0))
            return (
                Array(providers.prefix(splitIndex)),
                Array(providers.dropFirst(splitIndex))
            )
        }
    }

    @ViewBuilder
    private func usageLaneView(
        _ providers: [UsageProviderPresentation],
        alignment: Alignment
    ) -> some View {
        if providers.isEmpty {
            Color.clear
                .frame(maxWidth: .infinity)
        } else {
            ViewThatFits(in: .horizontal) {
                compactUsageSummaryView(providers, usesShortTitles: false)
                compactUsageSummaryView(providers, usesShortTitles: true)
            }
            .frame(maxWidth: .infinity, alignment: alignment)
        }
    }

    private func openedHeaderMetrics(for totalWidth: CGFloat) -> OpenedHeaderMetrics {
        let horizontalPadding = openedHeaderHorizontalPadding
        let contentWidth = max(0, totalWidth - (horizontalPadding * 2))
        guard usesNotchAwareOpenedHeader,
              let screen = targetOverlayScreen else {
            let rightLaneWidth = min(contentWidth, openedHeaderButtonsWidth + (contentWidth / 2))
            let leftUsageWidth = max(0, contentWidth - rightLaneWidth)
            return OpenedHeaderMetrics(
                leftUsageWidth: leftUsageWidth,
                centerGapWidth: 0,
                rightUsageWidth: max(0, rightLaneWidth - openedHeaderButtonsWidth - Self.headerControlSpacing),
                rightLaneWidth: rightLaneWidth
            )
        }

        let panelMinX = screen.frame.midX - (totalWidth / 2)
        let panelMaxX = panelMinX + totalWidth
        let contentMinX = panelMinX + horizontalPadding
        let contentMaxX = panelMaxX - horizontalPadding

        let fallbackNotchHalfWidth = screen.notchSize.width / 2
        let notchLeftEdge = screen.frame.midX - fallbackNotchHalfWidth
        let notchRightEdge = screen.frame.midX + fallbackNotchHalfWidth
        let leftVisibleMaxX = screen.auxiliaryTopLeftArea?.maxX ?? notchLeftEdge
        let rightVisibleMinX = screen.auxiliaryTopRightArea?.minX ?? notchRightEdge

        let rawLeftWidth = max(0, min(contentMaxX, leftVisibleMaxX) - contentMinX)
        let rawRightWidth = max(0, contentMaxX - max(contentMinX, rightVisibleMinX))

        let leftUsageWidth = max(0, rawLeftWidth - Self.notchLaneSafetyInset)
        let rightAvailableWidth = max(0, rawRightWidth - Self.notchLaneSafetyInset)
        let proposedRightUsageWidth = max(
            0,
            rightAvailableWidth - openedHeaderButtonsWidth - Self.headerControlSpacing
        )
        let rightUsageWidth = proposedRightUsageWidth >= Self.minimumRightUsageLaneWidth
            ? proposedRightUsageWidth
            : 0
        let rightLaneWidth = min(
            contentWidth,
            openedHeaderButtonsWidth
                + (rightUsageWidth > 0 ? Self.headerControlSpacing + rightUsageWidth : 0)
        )
        let centerGapWidth = max(0, contentWidth - leftUsageWidth - rightLaneWidth)

        return OpenedHeaderMetrics(
            leftUsageWidth: leftUsageWidth,
            centerGapWidth: centerGapWidth,
            rightUsageWidth: rightUsageWidth,
            rightLaneWidth: rightLaneWidth
        )
    }

    private func compactUsageSummaryView(
        _ providers: [UsageProviderPresentation],
        usesShortTitles: Bool
    ) -> some View {
        HStack(spacing: 7) {
            ForEach(providers) { provider in
                compactUsageChip(provider, usesShortTitle: usesShortTitles)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func compactUsageChip(_ provider: UsageProviderPresentation, usesShortTitle: Bool) -> some View {
        HStack(spacing: 5) {
            Text(usesShortTitle ? provider.shortTitle : provider.title)
                .font(.islandText(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.74))

            if model.settings.usage.showResetCards {
                // Every window, each with its own countdown. Off by default: the
                // busiest window is what usually matters and the header is narrow.
                ForEach(provider.windows) { window in
                    usageWindowFigures(window)
                }
            } else {
                peakUsageFigures(provider)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.white.opacity(0.055), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        )
        .help(usageHelpText(for: provider))
    }

    private func usageWindowFigures(_ window: UsageWindowPresentation) -> some View {
        HStack(spacing: 4) {
            Text(window.label)
                .font(.islandMono(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))

            Text(usageValueText(for: window.usedPercentage))
                .font(.islandMono(size: 11.5, weight: .bold))
                .foregroundStyle(usageColor(for: window.usedPercentage))

            if let resetsAt = window.resetsAt,
               let remaining = remainingDurationString(until: resetsAt) {
                Text(remaining)
                    .font(.islandMono(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.38))
            }
        }
    }

    private func peakUsageFigures(_ provider: UsageProviderPresentation) -> some View {
        HStack(spacing: 5) {
            Text(provider.peakWindowLabel)
                .font(.islandMono(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))

            Text(usageValueText(for: provider.peakUsedPercentage))
                .font(.islandMono(size: 11.5, weight: .bold))
                // Colour tracks how much is spent, never the printed figure —
                // "10% left" has to look as urgent as "90% used".
                .foregroundStyle(usageColor(for: provider.peakUsedPercentage))

            // Time to reset, inline. A percentage on its own does not answer
            // "can I keep going" — 90% with ten minutes left is fine, 90% with
            // four hours left is not.
            if let resetsAt = provider.peakWindow?.resetsAt,
               let remaining = remainingDurationString(until: resetsAt) {
                Text(remaining)
                    .font(.islandMono(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.38))
            }
        }
    }

    /// Formats one figure under the user's choice of counting up or down.
    private func usageValueText(for used: Double) -> String {
        let mode = model.settings.usage.valueMode
        let value = Int(mode.displayedPercentage(used: used).rounded())
        return mode == .remaining
            ? LanguageManager.shared.t("island.usage.remainingFormat").replacingOccurrences(of: "{value}", with: "\(value)")
            : "\(value)%"
    }

    private func usageHelpText(for provider: UsageProviderPresentation) -> String {
        provider.windows.map { window in
            var parts = ["\(window.label) \(usageValueText(for: window.usedPercentage))"]
            if let resetsAt = window.resetsAt,
               let remaining = remainingDurationString(until: resetsAt) {
                parts.append(remaining)
            }
            return parts.joined(separator: " ")
        }
        .joined(separator: " · ")
    }

    private func headerPill(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.islandText(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.08), in: Capsule())
    }

    private func usageColor(for percentage: Double) -> Color {
        switch percentage {
        case 90...:
            .red.opacity(0.95)
        case 70..<90:
            .orange.opacity(0.95)
        default:
            .green.opacity(0.95)
        }
    }

    private func remainingDurationString(until date: Date) -> String? {
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else {
            return nil
        }

        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated

        if interval >= 86_400 {
            formatter.allowedUnits = [.day]
            formatter.maximumUnitCount = 1
        } else if interval >= 3_600 {
            formatter.allowedUnits = [.hour, .minute]
            formatter.maximumUnitCount = 2
        } else {
            formatter.allowedUnits = [.minute]
            formatter.maximumUnitCount = 1
        }

        return formatter.string(from: interval)
    }
}

private struct UsageProviderPresentation: Identifiable {
    let id: String
    let title: String
    let windows: [UsageWindowPresentation]

    var peakWindow: UsageWindowPresentation? {
        windows.max { lhs, rhs in
            lhs.usedPercentage < rhs.usedPercentage
        }
    }

    var peakWindowLabel: String {
        peakWindow?.label ?? ""
    }

    var peakUsedPercentage: Double {
        peakWindow?.usedPercentage ?? 0
    }

    var peakUsagePercentage: Int {
        peakWindow?.roundedUsedPercentage ?? 0
    }

    var shortTitle: String {
        switch id {
        case "claude":
            "Cl"
        case "codex":
            "Cx"
        default:
            String(title.prefix(2))
        }
    }
}

private struct UsageWindowPresentation: Identifiable {
    let id: String
    let label: String
    let usedPercentage: Double
    let resetsAt: Date?

    var roundedUsedPercentage: Int {
        Int(usedPercentage.rounded())
    }
}

private struct OpenedHeaderMetrics {
    let leftUsageWidth: CGFloat
    let centerGapWidth: CGFloat
    let rightUsageWidth: CGFloat
    let rightLaneWidth: CGFloat
}

private struct SessionOverviewItem: Identifiable {
    let id: String
    let title: String
    let compactTitle: String
    let count: Int
    let tint: Color?
}

// MARK: - Session row (opened state)

private enum IslandSessionRowPresentation {
    case list
    case notification
}

private struct IslandSessionRow: View {
    let session: AgentSession
    let referenceDate: Date
    var stateIndicator: IslandSessionStateIndicator = .animatedDot
    var completedStaleThreshold: TimeInterval = AgentSession.staleCompletedDisplayThreshold
    var isActionable: Bool = false
    var useDrawingGroup: Bool = true
    var isInteractive: Bool = true
    var presentation: IslandSessionRowPresentation = .list
    var sideInset: CGFloat = 16
    var cardFields: IslandSessionCardFields = .all
    var lang: LanguageManager = .shared
    var onApprove: ((ApprovalAction) -> Void)?
    /// Answers every queued request at once. Nil when batching makes no sense.
    var onResolveAll: ((ApprovalAction) -> Void)?
    var pendingApprovalCount: Int = 1
    var onAnswer: ((QuestionPromptResponse) -> Void)?
    var onReply: ((String) -> Void)?
    let onJump: () -> Void
    var onDismiss: (() -> Void)?
    /// Adds a rule that keeps this kind of session off the island for good.
    var onHide: ((SilenceRule) -> Void)?
    var agentIconStyle: AgentIconStyle = .pixel
    /// Non-nil only while the shortcut modifier is held.
    var shortcutHint: ShortcutSettings?
    /// Draws the switcher's ring when this row is the one selected.
    var isSwitcherHighlighted = false
    /// Prefer a name derived from the first prompt over the workspace name.
    var usesAutoNaming = false

    @State private var isHighlighted = false
    @State private var detailOverride: Bool?
    @State private var replyText: String = ""

    var body: some View {
        rowBody(referenceDate: referenceDate)
    }

    private func rowBody(referenceDate: Date) -> some View {
        let rawPresence = session.islandPresence(at: referenceDate)
        let isStaleCompleted = session.isStaleCompletedForIsland(
            at: referenceDate,
            threshold: completedStaleThreshold
        )
        let defaultShowsDetail = !isStaleCompleted && (rawPresence != .inactive || isActionable)
        let showsDetail = detailOverride ?? defaultShowsDetail
        let presence = isStaleCompleted
            ? .inactive
            : ((showsDetail && rawPresence == .inactive) ? .active : rawPresence)
        return VStack(alignment: .leading, spacing: 0) {
            // Only the summary line jumps. The action area below it holds
            // approve/deny/answer controls, and a press on one of those must
            // not also count as "clicked this session".
            rowSummary(presence: presence, showsDetail: showsDetail)
                .contentShape(Rectangle())
                .onTapGesture(perform: handlePrimaryTap)
                .contextMenu { hideSessionMenuItems }

            if showsDetail {
                rowAuxiliaryDetails(presence: presence)

                if shouldShowEmbeddedDetailBody {
                    embeddedDetailBody
                        .padding(.leading, detailLeadingInset)
                        .padding(.trailing, sideInset)
                        .padding(.bottom, 13)
                }
            }
        }
        .background(rowFillColor(for: presence))
        .overlay(
            IslandThemes.current.shape(cornerRadius: 8)
                .strokeBorder(.white.opacity(isSwitcherHighlighted ? 0.55 : 0), lineWidth: 1.5)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.045))
                .frame(height: 1)
        }
        .overlay(alignment: .leading) {
            if showsLeadingStatusBar {
                IslandThemes.current.shape(cornerRadius: 999)
                    .fill(statusTint(for: presence))
                    // Thickens and lights up under the cursor, so the row you
                    // are about to click says which one it is.
                    .frame(width: isHighlighted ? 4 : 3)
                    .shadow(
                        color: isHighlighted
                            ? statusTint(for: presence).opacity(0.7)
                            : .clear,
                        radius: IslandThemes.current.glowRadius * 2
                    )
                    .padding(.vertical, showsDetail ? 10 : 8)
                    .padding(.leading, 14)
            }
        }
        .opacity(isStaleCompleted ? 0.7 : 1)
        // The drawing group flattens the row into a bitmap, which is why it is
        // off while hovering: a cached row cannot show a glow that changes.
        .modifier(ConditionalDrawingGroup(enabled: useDrawingGroup && !isActionable && !isHighlighted))
        .animation(.easeInOut(duration: 0.15), value: isHighlighted)
        // A session that changes state should be seen changing, not found
        // already changed the next time you look at the panel.
        .animation(.easeInOut(duration: 0.28), value: session.phase)
        .onHover { hovering in
            guard isInteractive, allowsRowHoverHighlight else { return }
            isHighlighted = hovering
        }
        .onChange(of: isInteractive) { _, interactive in
            if !interactive {
                detailOverride = nil
            }
        }
    }

    /// Right-click actions for keeping a session off the island for good.
    ///
    /// Writes an ordinary notification filter rather than a per-session flag:
    /// the same folder will produce a new session ID tomorrow, and a rule that
    /// only silenced today's would look broken.
    @ViewBuilder
    private var hideSessionMenuItems: some View {
        if onHide != nil, let directory = session.jumpTarget?.workingDirectory, !directory.isEmpty {
            Button(
                LanguageManager.shared.t("island.session.hideFolder")
                    .replacingOccurrences(of: "{name}", with: (directory as NSString).lastPathComponent)
            ) {
                onHide?(SilenceRule(field: .workingDirectory, match: .equals, pattern: directory))
            }
        }
        if onHide != nil, let app = session.jumpTarget?.terminalApp, !app.isEmpty {
            Button(
                LanguageManager.shared.t("island.session.hideApp")
                    .replacingOccurrences(of: "{name}", with: app)
            ) {
                onHide?(SilenceRule(field: .terminalApp, match: .equals, pattern: app))
            }
        }
    }

    private func rowSummary(presence: IslandSessionPresence, showsDetail: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if showsLeadingGlyphPair {
                // The list identifies sessions by agent + host marks; the
                // colour carries the state a dot used to carry on its own.
                SessionGlyphPair(
                    tool: session.tool,
                    terminalApp: session.jumpTarget?.terminalApp,
                    tint: statusTint(for: presence),
                    iconStyle: agentIconStyle,
                    usesScanlines: IslandThemes.current.cornerStyle == .chamfered
                )
                .frame(width: 30, alignment: .leading)
                .padding(.top, 4)
            } else if showsLeadingStatusIndicator {
                statusIndicator(for: presence)
                    .frame(width: 20, alignment: .top)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(summaryHeadlineText)
                    .font(summaryTitleFont)
                    .foregroundStyle(titleColor(for: presence))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if showsDetail,
                   let promptLine = summaryPromptLineText {
                    Text(promptLine)
                        .font(.islandText(size: 11.2, weight: .medium))
                        .foregroundStyle(summaryPromptColor(for: presence))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 10)

            HStack(spacing: 6) {
                if cardFields.showsProjectName, let project = session.spotlightProjectBadge {
                    sideBadge(project)
                }
                if cardFields.showsWorktree, let branch = session.claudeMetadata?.worktreeBranch,
                   !branch.isEmpty {
                    sideBadge(branch)
                }
                if cardFields.showsModel, let model = session.claudeMetadata?.model,
                   !model.isEmpty {
                    sideBadge(model)
                }
                agentBadge
                if session.isRemote {
                    sideBadge("SSH")
                }
                if let terminalBadge = session.spotlightTerminalBadge {
                    sideBadge(terminalBadge)
                }
                Text(session.spotlightAgeBadge)
                    .font(.islandMono(size: 10.5, weight: .medium))
                    .foregroundStyle(summaryAgeColor(for: presence))
                    .frame(minWidth: 30, alignment: .trailing)
                // List rows are a scannable index — one click jumps to the
                // session. A per-row disclosure chevron only competed with
                // that gesture and made the right edge noisy.
                if presentation != .list {
                    detailToggleButton(isOpen: showsDetail)
                }
                if let onDismiss {
                    DismissButton(action: onDismiss)
                }
            }
        }
        .padding(.leading, rowLeadingInset)
        .padding(.trailing, sideInset)
        .padding(.top, 11)
        .padding(.bottom, showsDetail ? 8 : 11)
    }

    @ViewBuilder
    private func rowAuxiliaryDetails(presence: IslandSessionPresence) -> some View {
        if cardFields.showsAgentActivity,
           !shouldShowEmbeddedDetailBody,
           let activityLine = resolvedActivityLine {
            Group {
                if activityLine.isToolInvocation {
                    // Tool name in the accent, its argument muted — the eye
                    // lands on "what is it doing" before "with what".
                    Text(activityLine.label)
                        .foregroundStyle(IslandDesignPalette.toolAccent)
                        + Text(activityLine.detail.map { " \($0)" } ?? "")
                        // Always muted, never the presence tint: a running row
                        // would otherwise print the whole line in the same
                        // blue and the tool name would stop standing out.
                        .foregroundStyle(V6Palette.paper.opacity(0.5))
                } else {
                    Text(activityLine.plainText)
                        .foregroundStyle(activityColor(for: presence).opacity(0.94))
                }
            }
            .font(.islandText(size: 11, weight: .medium))
            // One line in the list so every row is the same height; the
            // full text is one click away in the session itself.
            .lineLimit(presentation == .list ? 1 : 2)
            .padding(.leading, detailLeadingInset)
            .padding(.trailing, sideInset)
            .padding(.bottom, 10)
        }

        if cardFields.showsSubagents,
           let subagents = session.claudeMetadata?.activeSubagents,
           !subagents.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.islandText(size: 9, weight: .medium))
                    Text(lang.t("subagents.title", subagents.count))
                        .font(.islandText(size: 10.5, weight: .medium))
                }
                .foregroundStyle(.cyan.opacity(0.8))

                ForEach(subagents, id: \.agentID) { sub in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(sub.summary != nil
                                ? IslandDesignPalette.Status.completed
                                : IslandDesignPalette.Status.running)
                            .frame(width: 6, height: 6)
                        Text(sub.agentType ?? sub.agentID)
                            .font(.islandText(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                        if let desc = sub.taskDescription {
                            Text("(\(desc))")
                                .font(.islandText(size: 10.5))
                                .foregroundStyle(.white.opacity(0.5))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if sub.summary != nil {
                            Text(lang.t("subagents.completed"))
                                .font(.islandText(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.4))
                        } else if let started = sub.startedAt {
                            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                                Text(subagentElapsed(since: started, at: timeline.date))
                                    .font(.islandText(size: 10, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        }
                    }
                }
            }
            .padding(.leading, detailLeadingInset)
            .padding(.trailing, sideInset)
            .padding(.bottom, 10)
        }

        if cardFields.showsTasks,
           let tasks = session.claudeMetadata?.activeTasks,
           !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(taskSummary(tasks))
                    .font(.islandText(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                ForEach(tasks) { task in
                    HStack(spacing: 5) {
                        taskStatusIcon(task.status)
                        Text(task.title)
                            .font(.islandText(size: 10.5, weight: .medium))
                            .foregroundStyle(task.status == .completed
                                ? .white.opacity(0.4)
                                : .white.opacity(0.7))
                            .strikethrough(task.status == .completed)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.leading, detailLeadingInset)
            .padding(.trailing, sideInset)
            .padding(.bottom, 10)
        }
    }

    private var agentBadge: some View {
        let tint = Color(hex: session.tool.brandColorHex) ?? V6Palette.paper
        return Text(agentBadgeTitle)
            .font(.islandMono(size: 10.5, weight: .semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(tint.opacity(notificationChromeOpacity))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(notificationBadgeFillOpacity), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(notificationBadgeStrokeOpacity), lineWidth: 1))
    }

    private func sideBadge(_ title: String) -> some View {
        Text(title)
            .font(.islandMono(size: 10.5, weight: .medium))
            .lineLimit(1)
            .truncationMode(.tail)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(V6Palette.paper.opacity(presentation == .notification ? 0.52 : 0.7))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.white.opacity(presentation == .notification ? 0.045 : 0.06), in: Capsule())
    }

    private var summaryPromptLineText: String? {
        if presentation == .notification {
            if session.phase == .completed {
                return notificationCompletedPromptLineText
            }
            return session.notificationHeaderPromptLineText
        }

        return session.spotlightPromptLineText ?? expandedPromptLineText
    }

    private var summaryHeadlineText: String {
        if presentation == .notification, session.phase == .completed {
            return notificationWorkspaceHeadlineText
        }

        // Only when there is a prompt to derive from. Falling back to the
        // workspace is right: a blank headline would be worse than a repeated
        // one, which is the problem this setting exists to fix.
        if usesAutoNaming,
           let derived = SessionAutoName.derive(from: session.initialUserPromptText) {
            return derived
        }

        return session.spotlightHeadlineText
    }

    private var notificationWorkspaceHeadlineText: String {
        let workspace = session.spotlightWorkspaceName.trimmedForNotificationCard
        let title = workspace.isEmpty ? session.tool.displayName : workspace
        guard let branch = session.spotlightWorktreeBranch?.trimmedForNotificationCard,
              !branch.isEmpty else {
            return title
        }

        return "\(title) (\(branch))"
    }

    private var notificationCompletedPromptLineText: String? {
        if let prompt = session.latestUserPromptText?.trimmedForNotificationCard, !prompt.isEmpty {
            return lang.t("session.promptPrefix", prompt)
        }

        if let prompt = session.initialUserPromptText?.trimmedForNotificationCard, !prompt.isEmpty {
            return lang.t("session.promptPrefix", prompt)
        }

        return nil
    }

    private var agentBadgeTitle: String {
        switch session.tool {
        case .claudeCode:
            "claude"
        case .geminiCLI:
            "gemini"
        case .qwenCode:
            "qwen"
        case .kimiCLI:
            "kimi"
        default:
            session.tool.shortName.lowercased()
        }
    }

    private var rowLeadingInset: CGFloat {
        if presentation == .notification {
            return sideInset
        }

        return switch stateIndicator {
        case .bar:
            max(28, sideInset)
        case .tint:
            sideInset
        case .animatedDot, .glyph:
            sideInset
        }
    }

    private var detailLeadingInset: CGFloat {
        if presentation == .notification {
            return sideInset
        }

        return switch stateIndicator {
        case .bar:
            max(28, sideInset)
        case .tint:
            sideInset
        case .animatedDot, .glyph:
            sideInset + 30
        }
    }

    private var showsLeadingGlyphPair: Bool {
        presentation == .list && stateIndicator != .tint && stateIndicator != .bar
    }

    private var showsLeadingStatusIndicator: Bool {
        false
    }

    private var showsLeadingStatusBar: Bool {
        presentation == .list && stateIndicator == .bar
    }

    private var summaryTitleFont: Font {
        .system(size: presentation == .notification ? 13.2 : (isActionable ? 13.8 : 13.2), weight: .semibold)
    }

    private func summaryPromptColor(for presence: IslandSessionPresence) -> Color {
        if presentation == .notification {
            return V6Palette.paper.opacity(session.phase == .completed ? 0.38 : 0.46)
        }

        return V6Palette.paper.opacity(presence == .inactive ? 0.34 : 0.52)
    }

    private func summaryAgeColor(for presence: IslandSessionPresence) -> Color {
        if presentation == .notification {
            return V6Palette.paper.opacity(0.36)
        }

        return V6Palette.paper.opacity(presence == .inactive ? 0.32 : 0.45)
    }

    private var notificationChromeOpacity: Double {
        presentation == .notification ? 0.82 : 1
    }

    private var notificationBadgeFillOpacity: Double {
        presentation == .notification ? 0.08 : 0.13
    }

    private var notificationBadgeStrokeOpacity: Double {
        presentation == .notification ? 0.24 : 0.35
    }

    private func titleColor(for presence: IslandSessionPresence) -> Color {
        if stateIndicator == .tint && presence != .inactive {
            return statusTint(for: presence)
        }

        if presentation == .notification, session.phase == .completed {
            return .white.opacity(0.78)
        }

        return headlineColor(for: presence)
    }

    private var actionableBorderColor: Color {
        if isActionable {
            return actionableStatusTint.opacity(isHighlighted ? 0.45 : 0.28)
        }
        return isHighlighted ? .white.opacity(0.24) : .white.opacity(0.04)
    }

    private var actionableStatusTint: Color {
        IslandDesignPalette.Status.tint(for: session.phase)
    }

    @ViewBuilder
    private var actionableBody: some View {
        switch session.phase {
        case .waitingForApproval:
            approvalActionBody
        case .waitingForAnswer:
            questionActionBody
        case .completed:
            completionActionBody
        case .running:
            EmptyView()
        }
    }

    private var shouldShowEmbeddedDetailBody: Bool {
        if session.phase.requiresAttention {
            return true
        }
        if session.phase == .completed {
            return isActionable && completionHasExpandedBody
        }
        // List rows stay at a fixed three lines — title, the user's prompt, and
        // the tool currently running. Letting the assistant body in made row
        // heights jump between 70pt and 140pt, so the number of sessions
        // visible without scrolling changed every time an agent replied.
        // Notification and actionable cards still show the body.
        guard presentation != .list else {
            return false
        }
        return session.phase == .running && runningDetailText != nil
    }

    private var completionHasExpandedBody: Bool {
        !completionMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || onReply != nil
    }

    @ViewBuilder
    private var embeddedDetailBody: some View {
        switch session.phase {
        case .waitingForApproval, .waitingForAnswer, .completed:
            actionableBody
        case .running:
            runningDetailBody
        }
    }

    private var runningDetailBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let runningDetailText {
                Text(runningDetailText)
                    .font(.islandMono(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        IslandThemes.current.shape(cornerRadius: 7)
                            .fill(Color.white.opacity(0.045))
                    )
                    .overlay(
                        IslandThemes.current.shape(cornerRadius: 7)
                            .strokeBorder(.white.opacity(0.06))
                    )
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Approval action area

    private var approvalActionBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(lang.t(isPlanApproval ? "approval.planReady" : "approval.toolPermissionRequested"))
                    .font(.islandText(size: 12.5, weight: .semibold))
                    .foregroundStyle(V6Palette.paper.opacity(0.86))

                if pendingApprovalCount > 1 {
                    Text(lang.t("approval.pendingCount", String(pendingApprovalCount)))
                        .font(.islandMono(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Color.white.opacity(0.1), in: Capsule())
                        .foregroundStyle(V6Palette.paper.opacity(0.6))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(commandPreviewText)
                    .font(.islandMono(size: 11.5, weight: .semibold))
                    .foregroundStyle(V6Palette.paper.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)

                if let path = session.permissionRequest?.affectedPath.trimmedForNotificationCard,
                   !path.isEmpty {
                    Text(path)
                        .font(.islandText(size: 10.5, weight: .medium))
                        .foregroundStyle(V6Palette.paper.opacity(0.42))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                IslandThemes.current.shape(cornerRadius: 7)
                    .fill(Color.white.opacity(0.045))
            )

            HStack(spacing: 8) {
                Button(shortcutHinted(session.permissionRequest?.secondaryActionTitle ?? lang.t("approval.deny"), .deny)) {
                    onApprove?(.deny)
                }
                .buttonStyle(IslandActionButtonStyle(kind: .secondary, expands: true))
                Button(shortcutHinted(session.permissionRequest?.primaryActionTitle ?? lang.t("approval.allowOnce"), .approve)) {
                    onApprove?(.allowOnce)
                }
                .buttonStyle(IslandActionButtonStyle(kind: .warning, expands: true))
            }

            // Whatever else the agent offered — "bypass permissions",
            // "accept edits", a scoped always-allow. These arrive in
            // `suggestedUpdates` and used to be dropped on the floor, which left
            // the island unable to answer a plan-mode exit at all.
            ForEach(Array(suggestedApprovalUpdates.enumerated()), id: \.offset) { _, update in
                Button(update.displayLabel) {
                    onApprove?(.allowWithUpdates([update]))
                }
                .buttonStyle(IslandActionButtonStyle(kind: .primary, expands: true))
            }

            // Only worth offering when there is more than one thing queued.
            if pendingApprovalCount > 1 {
                HStack(spacing: 8) {
                    Button(lang.t("approval.denyAll")) { onResolveAll?(.deny) }
                        .buttonStyle(IslandActionButtonStyle(kind: .secondary, expands: true))
                    Button(lang.t("approval.allowAll")) { onResolveAll?(.allowOnce) }
                        .buttonStyle(IslandActionButtonStyle(kind: .secondary, expands: true))
                }
            }

            Button(shortcutHinted(lang.t("approval.goToTerminal"), .jumpToTerminal)) { onJump() }
                .buttonStyle(IslandActionButtonStyle(kind: .secondary, expands: true))
        }
    }

    /// Appends the key that also triggers this button, but only while the
    /// modifier is held — a permanent "⌃Y" on every button is clutter, and one
    /// that appears on demand is a reminder.
    private func shortcutHinted(_ title: String, _ action: PanelShortcutAction) -> String {
        guard let hint = shortcutHint else { return title }
        return "\(title)  \(hint.modifier.symbol)\(hint.key(for: action))"
    }

    /// The agent's own options, falling back to a session-scoped always-allow
    /// when it offered none — which is what the card used to hard-code.
    private var suggestedApprovalUpdates: [ClaudePermissionUpdate] {
        if let suggested = session.permissionRequest?.suggestedUpdates, !suggested.isEmpty {
            return suggested
        }
        guard let toolName = session.permissionRequest?.toolName else { return [] }
        return [
            .addRules(
                destination: .session,
                rules: [ClaudePermissionRuleValue(toolName: toolName)],
                behavior: .allow
            )
        ]
    }

    // MARK: - Question action area

    private var questionActionBody: some View {
        StructuredQuestionPromptView(
            prompt: session.questionPrompt,
            lang: lang,
            onAnswer: { onAnswer?($0) }
        )
    }

    // MARK: - Completion action area

    private var completionActionBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !completionMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                AutoHeightScrollView(maxHeight: 240) {
                    Markdown(completionMessageText)
                        .markdownTheme(.completionCard)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                }
            } else {
                completionEmptyState
            }

            if onReply != nil {
                Rectangle()
                    .fill(.white.opacity(completionDividerOpacity))
                    .frame(height: 1)

                completionReplyInput
            }
        }
        .background(
            IslandThemes.current.shape(cornerRadius: 10)
                .fill(Color.white.opacity(completionCardFillOpacity))
        )
        .overlay(
            IslandThemes.current.shape(cornerRadius: 10)
                .strokeBorder(.white.opacity(completionCardStrokeOpacity))
        )
    }

    private var completionDoneOpacity: Double {
        presentation == .notification ? 0.82 : 0.96
    }

    private var completionDividerOpacity: Double {
        presentation == .notification ? 0.035 : 0.04
    }

    private var completionCardFillOpacity: Double {
        presentation == .notification ? 0.035 : 0.045
    }

    private var completionCardStrokeOpacity: Double {
        presentation == .notification ? 0.06 : 0.08
    }

    private var completionEmptyState: some View {
        HStack {
            Text(lang.t("completion.done"))
                .font(.islandText(size: 11.5, weight: .bold))
                .foregroundStyle(IslandDesignPalette.Status.completed.opacity(completionDoneOpacity))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var completionReplyInput: some View {
        HStack(spacing: 8) {
            ReplyTextField(
                placeholder: lang.t("completion.replyPlaceholder", session.completionReplyRecipientName),
                text: $replyText,
                onSubmit: { submitReply() }
            )
            .frame(height: 32)

            Button {
                submitReply()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.islandText(size: 24))
                    .foregroundColor(replyText.trimmingCharacters(in: .whitespaces).isEmpty
                        ? .white.opacity(0.2) : .white.opacity(0.9))
            }
            .buttonStyle(.plain)
            .disabled(replyText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func submitReply() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        replyText = ""
        onReply?(text)
    }

    // MARK: - Actionable helpers

    private var completionMessageText: String {
        if let text = session.completionAssistantMessageText?.trimmedForNotificationCard, !text.isEmpty {
            return text
        }
        let summary = session.summary.trimmedForNotificationCard
        return summary == SessionPhase.completed.displayName ? "" : summary
    }

    private var commandLabel: String {
        switch session.currentToolName {
        case "exec_command", "Bash": return "Bash"
        case "AskUserQuestion": return "Question"
        case "ExitPlanMode": return "Plan"
        case "apply_patch": return "Patch"
        case "write_stdin": return "Input"
        case let value?: return AgentSession.currentToolDisplayName(for: value)
        case nil: return "Command"
        }
    }

    private var commandPreviewText: String {
        let preview = session.currentCommandPreviewText?.trimmedForNotificationCard
        if let preview, !preview.isEmpty {
            // A shell prompt in front of a plan reads as a command to run.
            return isPlanApproval ? preview : "$ \(preview)"
        }
        return session.permissionRequest?.summary.trimmedForNotificationCard ?? session.summary.trimmedForNotificationCard
    }

    /// Leaving plan mode is a decision about how to proceed, not a tool call.
    private var isPlanApproval: Bool {
        session.permissionRequest?.toolName == "ExitPlanMode"
    }

    private var runningDetailText: String? {
        if let preview = session.currentCommandPreviewText?.trimmedForNotificationCard,
           !preview.isEmpty {
            return "$ \(preview)"
        }

        if let activity = session.spotlightActivityLineText?.trimmedForNotificationCard,
           !activity.isEmpty {
            return activity
        }

        let summary = session.summary.trimmedForNotificationCard
        return summary.isEmpty ? nil : summary
    }

    private func subagentElapsed(since start: Date, at now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(start))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let secs = seconds % 60
        return "\(minutes)m \(secs)s"
    }

    private func taskSummary(_ tasks: [ClaudeTaskInfo]) -> String {
        let done = tasks.filter { $0.status == .completed }.count
        let prog = tasks.filter { $0.status == .inProgress }.count
        let pend = tasks.filter { $0.status == .pending }.count
        return lang.t("tasks.summary", done, prog, pend)
    }

    @ViewBuilder
    private func taskStatusIcon(_ status: ClaudeTaskInfo.Status) -> some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark.square.fill")
                .font(.islandText(size: 9))
                .foregroundStyle(.white.opacity(0.35))
        case .inProgress:
            Circle()
                .fill(IslandDesignPalette.Status.running)
                .frame(width: 6, height: 6)
        case .pending:
            Circle()
                .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                .frame(width: 6, height: 6)
        }
    }

    @ViewBuilder
    private func statusIndicator(for presence: IslandSessionPresence) -> some View {
        let tint = statusTint(for: presence)
        switch stateIndicator {
        case .animatedDot:
            if let interval = stateIndicator.timelineInterval(presence: presence, isActionable: isActionable) {
                TimelineView(.periodic(from: .now, by: interval)) { context in
                    let pulse = (sin(context.date.timeIntervalSinceReferenceDate * 3.2) + 1) / 2
                    statusDot(tint: tint, presence: presence, pulse: pulse)
                }
                .frame(width: 10, height: 24, alignment: .top)
            } else {
                statusDot(tint: tint, presence: presence, pulse: 0)
                    .frame(width: 10, height: 24, alignment: .top)
            }
        case .bar:
            IslandThemes.current.shape(cornerRadius: 2.5)
                .fill(tint)
                .frame(width: 4, height: isActionable ? 34 : 28)
                .padding(.top, 2)
        case .glyph:
            Image(systemName: statusGlyphName)
                .font(.islandText(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 14, height: 20)
                .padding(.top, 1)
        case .tint:
            Circle()
                .fill(tint.opacity(presence == .inactive ? 0.54 : 0.92))
                .frame(width: 8, height: 8)
                .padding(.top, 6)
        }
    }

    private func statusDot(tint: Color, presence: IslandSessionPresence, pulse: Double) -> some View {
        Circle()
            .fill(tint)
            .frame(width: 9, height: 9)
            .scaleEffect(1 + (pulse * 0.18))
            .shadow(color: tint.opacity(presence == .inactive ? 0 : 0.36 + (pulse * 0.26)), radius: 4 + (pulse * 3))
            .padding(.top, 6)
    }

    private func rowFillColor(for presence: IslandSessionPresence) -> Color {
        if presentation == .notification {
            return Color.clear
        }

        // Tinted with the accent rather than plain white: at the 4% a white
        // veil needs to stay unobtrusive, the row barely changed at all and the
        // list read as a static picture. A coloured wash at the same weight is
        // visible without being loud.
        let base = isHighlighted
            ? IslandThemes.current.accent.opacity(isActionable ? 0.13 : 0.09)
            : Color.clear
        guard stateIndicator == .tint else { return base }

        let tintOpacity: Double
        if isHighlighted {
            tintOpacity = isActionable ? 0.16 : 0.11
        } else {
            tintOpacity = presence == .inactive ? 0.035 : 0.075
        }
        return statusTint(for: presence).opacity(tintOpacity)
    }

    private var statusGlyphName: String {
        switch session.phase {
        case .waitingForApproval:
            "exclamationmark.triangle.fill"
        case .waitingForAnswer:
            "questionmark.circle.fill"
        case .running:
            "circle.dashed"
        case .completed:
            "checkmark.circle.fill"
        }
    }

    private var allowsRowHoverHighlight: Bool {
        presentation != .notification
    }

    /// Prompt line for manually expanded inactive rows (bypasses time-based filter).
    private var expandedPromptLineText: String? {
        guard detailOverride == true, let prompt = session.spotlightPromptText else { return nil }
        return lang.t("session.promptPrefix", prompt)
    }

    /// Activity line for manually expanded inactive rows (bypasses time-based filter).
    private var expandedActivityLine: IslandActivityLine? {
        guard detailOverride == true else { return nil }
        let trimmed = session.lastAssistantMessageText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let assistantMessage = trimmed, !assistantMessage.isEmpty {
            return IslandActivityLine(label: assistantMessage)
        }
        return IslandActivityLine(label: lang.t(session.jumpTarget != nil ? "session.ready" : "session.completed"))
    }

    private var resolvedActivityLine: IslandActivityLine? {
        session.spotlightActivityLine ?? expandedActivityLine
    }

    private func handlePrimaryTap() {
        guard isInteractive else { return }
        onJump()
    }

    private func detailToggleButton(isOpen: Bool) -> some View {
        Button {
            guard isInteractive else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                detailOverride = !isOpen
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.islandText(size: 10, weight: .bold))
                .foregroundStyle(isOpen || isHighlighted ? .white.opacity(0.68) : .white.opacity(0.42))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(.white.opacity(detailToggleFillOpacity(isOpen: isOpen)))
                )
                .rotationEffect(.degrees(isOpen ? 180 : 0))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOpen ? "Collapse session detail" : "Expand session detail")
    }

    private func detailToggleFillOpacity(isOpen: Bool) -> Double {
        if isHighlighted {
            return isOpen ? 0.075 : 0.055
        }

        return isOpen ? 0.045 : 0.02
    }

    private func compactBadge(
        _ title: String,
        presence: IslandSessionPresence,
        icon: String? = nil
    ) -> some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(.islandText(size: 7.5, weight: .semibold))
            }
            Text(title)
                .font(.islandText(size: 9, weight: .semibold))
        }
        .foregroundStyle(badgeTextColor(for: presence))
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .background(Color(red: 0.14, green: 0.14, blue: 0.15), in: Capsule())
    }

    private func headlineColor(for presence: IslandSessionPresence) -> Color {
        presence == .inactive ? .white.opacity(0.78) : .white
    }

    private func badgeTextColor(for presence: IslandSessionPresence) -> Color {
        presence == .inactive ? .white.opacity(0.42) : .white.opacity(0.56)
    }

    private func statusTint(for presence: IslandSessionPresence) -> Color {
        IslandDesignPalette.Status.tint(for: session.phase, presence: presence)
    }

    private func activityColor(for presence: IslandSessionPresence) -> Color {
        switch session.spotlightActivityTone {
        case .attention:
            IslandDesignPalette.Status.tint(for: session.phase)
        case .live:
            statusTint(for: presence)
        case .idle:
            .white.opacity(0.46)
        case .ready:
            presence == .inactive ? .white.opacity(0.46) : statusTint(for: presence)
        }
    }
}

private struct StructuredQuestionPromptView: View {
    let prompt: QuestionPrompt?
    var lang: LanguageManager = .shared
    let onAnswer: (QuestionPromptResponse) -> Void

    @State private var selections: [String: Set<String>] = [:]
    @State private var freeformTexts: [String: String] = [:]
    @State private var typedReply: String = ""
    @State private var hoveredOptionKey: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsPromptTitle {
                Text(promptTitle)
                    .font(.islandText(size: 13, weight: .semibold))
                    .foregroundStyle(IslandDesignPalette.Status.waitingForAnswer)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if structuredQuestions.isEmpty {
                freeformAnswerBody
            } else {
                // Deliberately every question at once rather than one per page.
                // The panel already scrolls, and paging hides how much is left
                // to answer — which is the thing the user wants to know.
                if structuredQuestions.count > 1 {
                    Text(lang.t(
                        "question.progress",
                        String(answeredQuestionCount),
                        String(structuredQuestions.count)
                    ))
                    .font(.islandMono(size: 10, weight: .medium))
                    .foregroundStyle(V6Palette.paper.opacity(0.5))
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(structuredQuestions, id: \.question) { question in
                        questionRow(question)
                    }
                }

                quickReplyField

                // Says why the button is inert instead of leaving the user to
                // hunt for the question they missed.
                if !canSubmit, answeredQuestionCount < structuredQuestions.count {
                    Text(lang.t("question.answerAllFirst"))
                        .font(.islandText(size: 10.5, weight: .medium))
                        .foregroundStyle(IslandDesignPalette.Status.waitingForAnswer.opacity(0.8))
                }

                Button(submitButtonTitle) {
                    submitAnswer()
                }
                .buttonStyle(IslandActionButtonStyle(kind: canSubmit ? .primary : .secondary, expands: true))
                .disabled(!canSubmit)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            IslandThemes.current.shape(cornerRadius: 10)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            IslandThemes.current.shape(cornerRadius: 10)
                .strokeBorder(.white.opacity(0.05))
        )
    }

    // MARK: - Per-question row

    /// Renders a single question with its header, text, and vertical option list.
    @ViewBuilder
    private func questionRow(_ question: QuestionPromptItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if structuredQuestions.count > 1 {
                Text(question.header)
                    .font(.islandText(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Text(question.question)
                .font(.islandText(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(question.options.enumerated()), id: \.element.id) { index, option in
                    optionRow(option, optionIndex: index, question: question)
                }
            }
        }
    }

    // MARK: - Option row (vertical, CLI-style)

    @ViewBuilder
    private func optionRow(
        _ option: QuestionOption,
        optionIndex: Int,
        question: QuestionPromptItem
    ) -> some View {
        let isSelected = selectedLabels(for: question).contains(option.label)
        let key = optionKey(for: question, option: option)
        let isHovered = hoveredOptionKey == key
        let showsFreeform = option.allowsFreeform && isSelected
        VStack(alignment: .leading, spacing: 0) {
            Button {
                toggle(option: option.label, for: question)
            } label: {
                HStack(spacing: 10) {
                    Text("\(optionIndex + 1)")
                        .font(.islandMono(size: 10.5, weight: .semibold))
                        .foregroundStyle(isSelected ? .black.opacity(0.82) : V6Palette.paper.opacity(0.42))
                        .frame(width: 22, height: 20)
                        .background(
                            IslandThemes.current.shape(cornerRadius: 5)
                                .fill(isSelected ? V6Palette.paper.opacity(0.88) : Color.white.opacity(0.045))
                        )
                        .overlay(
                            IslandThemes.current.shape(cornerRadius: 5)
                                .strokeBorder(.white.opacity(isSelected ? 0 : 0.08))
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(option.label)
                            .font(.islandText(size: 12.2, weight: .medium))
                            .foregroundStyle(.white.opacity(isSelected ? 1 : 0.78))

                        if !option.description.isEmpty {
                            Text(option.description)
                                .font(.islandText(size: 10.5))
                                .foregroundStyle(.white.opacity(isHovered || isSelected ? 0.48 : 0.38))
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.islandText(size: 11, weight: .bold))
                            .foregroundStyle(IslandDesignPalette.Status.completed)
                    }
                }
                .contentShape(Rectangle())
                .padding(.vertical, 5)
                .padding(.horizontal, 11)
            }
            .buttonStyle(.plain)

            if showsFreeform {
                Divider()
                    .overlay(Color.white.opacity(0.08))
                freeformField(for: option, question: question)
            }
        }
        .background(
            IslandThemes.current.shape(cornerRadius: 8)
                .fill(optionFillColor(isSelected: isSelected, isHovered: isHovered))
        )
        .overlay(
            IslandThemes.current.shape(cornerRadius: 8)
                .strokeBorder(optionStrokeColor(isSelected: isSelected, isHovered: isHovered))
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                hoveredOptionKey = hovering ? key : (hoveredOptionKey == key ? nil : hoveredOptionKey)
            }
        }
    }

    @ViewBuilder
    private func freeformField(for option: QuestionOption, question: QuestionPromptItem) -> some View {
        let key = freeformKey(for: question, option: option)
        ReplyTextField(
            placeholder: lang.t("question.otherPlaceholder"),
            text: Binding(
                get: { freeformTexts[key] ?? "" },
                set: { freeformTexts[key] = $0 }
            ),
            onSubmit: {
                if hasCompleteSelection {
                    onAnswer(QuestionPromptResponse(answers: answerMap))
                }
            }
        )
        .frame(height: 22)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
    }

    private var freeformAnswerBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            quickReplyField

            Button(lang.t("question.submit")) {
                submitAnswer()
            }
            .buttonStyle(IslandActionButtonStyle(kind: canSubmit ? .primary : .secondary, expands: true))
            .disabled(!canSubmit)
        }
    }

    @ViewBuilder
    private var quickReplyField: some View {
        if showsGlobalReplyField {
            HStack(spacing: 6) {
                ReplyTextField(
                    placeholder: lang.t("question.otherPlaceholder"),
                    text: $typedReply,
                    onSubmit: {
                        if canSubmit {
                            submitAnswer()
                        }
                    }
                )
                .frame(height: 30)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                IslandThemes.current.shape(cornerRadius: 10)
                    .fill(Color.white.opacity(0.035))
            )
            .overlay(
                IslandThemes.current.shape(cornerRadius: 10)
                    .strokeBorder(.white.opacity(0.055))
            )
        }
    }

    // MARK: - Helpers

    private var structuredQuestions: [QuestionPromptItem] {
        if let questions = prompt?.questions, !questions.isEmpty {
            return questions
        }

        guard let prompt, !prompt.options.isEmpty else {
            return []
        }

        return [
            QuestionPromptItem(
                question: prompt.title,
                header: lang.t("question.answerNeeded"),
                options: prompt.options.map { QuestionOption(label: $0) }
            ),
        ]
    }

    private var promptTitle: String {
        prompt?.title.trimmedForNotificationCard ?? lang.t("question.answerNeeded")
    }

    private var showsPromptTitle: Bool {
        guard !promptTitle.isEmpty else {
            return false
        }

        guard structuredQuestions.count == 1,
              let questionTitle = structuredQuestions.first?.question.trimmedForNotificationCard else {
            return true
        }

        return questionTitle.caseInsensitiveCompare(promptTitle) != .orderedSame
    }

    private var answerMap: [String: String] {
        Dictionary(uniqueKeysWithValues: structuredQuestions.compactMap { question in
            let values = resolvedAnswers(for: question)
            guard !values.isEmpty else {
                return nil
            }
            return (question.question, values.joined(separator: ", "))
        })
    }

    private var trimmedReply: String {
        typedReply.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showsGlobalReplyField: Bool {
        structuredQuestions.isEmpty || !structuredQuestions.contains { question in
            question.options.contains { $0.allowsFreeform }
        }
    }

    private var primarySelectedAnswer: String? {
        guard structuredQuestions.count == 1,
              let question = structuredQuestions.first else {
            return nil
        }

        let values = resolvedAnswers(for: question)
        guard !values.isEmpty else {
            return nil
        }

        return values.joined(separator: ", ")
    }

    private var canSubmit: Bool {
        !trimmedReply.isEmpty || (!structuredQuestions.isEmpty && hasCompleteSelection)
    }

    private var submitButtonTitle: String {
        if !trimmedReply.isEmpty {
            return lang.t("question.sendReply")
        }

        if let primarySelectedAnswer, !primarySelectedAnswer.isEmpty {
            return lang.t("question.sendAnswer")
        }

        return lang.t("question.submit")
    }

    private func submitAnswer() {
        if !trimmedReply.isEmpty {
            onAnswer(QuestionPromptResponse(answer: trimmedReply))
            return
        }

        onAnswer(
            QuestionPromptResponse(
                rawAnswer: primarySelectedAnswer,
                answers: answerMap
            )
        )
    }

    /// How many questions have a usable answer, for the progress line.
    var answeredQuestionCount: Int {
        structuredQuestions.filter(isAnswered).count
    }

    private func isAnswered(_ question: QuestionPromptItem) -> Bool {
        let selected = selectedLabels(for: question)
        guard !selected.isEmpty else { return false }
        for option in question.options where option.allowsFreeform && selected.contains(option.label) {
            if trimmedFreeform(for: question, option: option).isEmpty {
                return false
            }
        }
        return true
    }

    private var hasCompleteSelection: Bool {
        structuredQuestions.allSatisfy { question in
            let selected = selectedLabels(for: question)
            guard !selected.isEmpty else {
                return false
            }
            // When a freeform option is selected, require non-empty text.
            for option in question.options where option.allowsFreeform && selected.contains(option.label) {
                if trimmedFreeform(for: question, option: option).isEmpty {
                    return false
                }
            }
            return true
        }
    }

    private func selectedLabels(for question: QuestionPromptItem) -> Set<String> {
        selections[question.question] ?? []
    }

    private func resolvedAnswers(for question: QuestionPromptItem) -> [String] {
        let selected = selectedLabels(for: question)
        guard !selected.isEmpty else { return [] }

        let optionOrder = question.options
        var answers: [String] = []
        for option in optionOrder where selected.contains(option.label) {
            if option.allowsFreeform {
                let text = trimmedFreeform(for: question, option: option)
                answers.append(text.isEmpty ? option.label : text)
            } else {
                answers.append(option.label)
            }
        }
        return answers
    }

    private func freeformKey(for question: QuestionPromptItem, option: QuestionOption) -> String {
        "\(question.question)|\(option.label)"
    }

    private func optionKey(for question: QuestionPromptItem, option: QuestionOption) -> String {
        "\(question.question)|\(option.label)"
    }

    private func optionFillColor(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return V6Palette.paper.opacity(0.10)
        }
        if isHovered {
            return Color.white.opacity(0.065)
        }
        return Color.white.opacity(0.028)
    }

    private func optionStrokeColor(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return V6Palette.paper.opacity(0.36)
        }
        if isHovered {
            return .white.opacity(0.13)
        }
        return .white.opacity(0.045)
    }

    private func trimmedFreeform(for question: QuestionPromptItem, option: QuestionOption) -> String {
        (freeformTexts[freeformKey(for: question, option: option)] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func toggle(option: String, for question: QuestionPromptItem) {
        var selected = selections[question.question] ?? []

        if question.multiSelect {
            if selected.contains(option) {
                selected.remove(option)
            } else {
                selected.insert(option)
            }
        } else {
            if selected.contains(option) {
                selected.removeAll()
            } else {
                selected = [option]
            }
        }

        typedReply = ""
        selections[question.question] = selected
    }
}

// MARK: - Reply TextField (NSTextField wrapper for IME-safe Enter handling)

/// NSTextField wrapper that fires `onSubmit` only when the IME composition
/// is finished — pressing Enter during Chinese/Japanese IME composition
/// confirms the candidate instead of submitting.
private struct ReplyTextField: NSViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.textColor = .white
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.35),
                .font: NSFont.systemFont(ofSize: 13),
            ]
        )
        field.delegate = context.coordinator
        field.cell?.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        context.coordinator.onSubmit = onSubmit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Let AppKit handle Enter during IME composition (e.g. confirming
                // a Chinese/Japanese candidate). Only submit when no marked text.
                guard !textView.hasMarkedText() else { return false }
                onSubmit()
                return true
            }
            return false
        }
    }
}

private extension String {
    var trimmedForNotificationCard: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Compact button style

private struct IslandCompactButtonStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.islandText(size: 10, weight: .semibold))
            .foregroundStyle(tint == .secondary ? .white.opacity(0.7) : tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                (tint == .secondary ? Color.white.opacity(0.08) : tint.opacity(0.15)),
                in: Capsule()
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The buttons on an approval or question card.
///
/// A `ButtonStyle` cannot hold `@State`, so the hover treatment lives in a
/// nested view. Before this, the only feedback a button gave was a dip in
/// opacity *after* it had been clicked — nothing told you it was pressable
/// while your cursor was on it, which is what made the panel feel dead.
private struct IslandActionButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
        case warning
    }

    let kind: Kind
    var expands = false

    func makeBody(configuration: Configuration) -> some View {
        IslandActionButtonBody(kind: kind, expands: expands, configuration: configuration)
    }
}

private struct IslandActionButtonBody: View {
    let kind: IslandActionButtonStyle.Kind
    let expands: Bool
    let configuration: ButtonStyle.Configuration

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    private var theme: any IslandTheme { IslandThemes.current }
    private var isPressed: Bool { configuration.isPressed }
    /// A disabled button must not light up under the cursor — that would
    /// promise something it cannot do.
    private var isLit: Bool { isHovering && isEnabled }

    var body: some View {
        configuration.label
            .font(.islandText(size: 11.8, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .frame(maxWidth: expands ? .infinity : nil)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(theme.shape(cornerRadius: 10).fill(backgroundColor))
            .overlay(theme.shape(cornerRadius: 10).stroke(strokeColor, lineWidth: 1))
            .overlay(alignment: .bottomLeading) { hoverUnderline }
            .clipShape(theme.shape(cornerRadius: 10))
            // A press has to feel like the button moved, not merely faded.
            .scaleEffect(isPressed ? 0.97 : 1)
            .shadow(color: glowColor, radius: isLit ? theme.glowRadius * 2 : 0)
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .animation(.easeOut(duration: 0.08), value: isPressed)
            .onHover { isHovering = $0 }
    }

    /// A one-pixel line that grows in from the left edge. Cheap to draw, and it
    /// reads as the control waking up rather than merely changing colour.
    @ViewBuilder
    private var hoverUnderline: some View {
        Rectangle()
            .fill(accentLine)
            .frame(height: 1.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .scaleEffect(x: isLit ? 1 : 0, anchor: .leading)
            .opacity(isLit ? 1 : 0)
    }

    private var accentLine: Color {
        switch kind {
        case .primary: theme.ink.opacity(0.55)
        case .warning: .white.opacity(0.7)
        case .secondary: theme.accent
        }
    }

    private var glowColor: Color {
        guard isLit else { return .clear }
        return kind == .secondary ? theme.accent.opacity(0.4) : .clear
    }

    private var foregroundColor: Color {
        guard isEnabled else { return theme.paper.opacity(0.42) }

        switch kind {
        case .primary: return theme.ink.opacity(0.9)
        case .warning: return .white
        case .secondary: return theme.paper.opacity(isLit ? 1 : 0.78)
        }
    }

    private var strokeColor: Color {
        guard isEnabled else { return .white.opacity(0.07) }

        switch kind {
        case .primary:
            return theme.paper.opacity(0.86)
        case .warning:
            return theme.statusTints.waitingForApproval.opacity(isLit ? 0.85 : 0.42)
        case .secondary:
            return isLit ? theme.accent.opacity(0.55) : .white.opacity(0.07)
        }
    }

    private var backgroundColor: Color {
        guard isEnabled else { return .white.opacity(0.055) }

        let pressedFactor: Double = isPressed ? 0.78 : 1
        switch kind {
        case .primary:
            return theme.paper.opacity(pressedFactor)
        case .warning:
            return theme.statusTints.waitingForApproval
                .opacity(pressedFactor * (isLit ? 1 : 0.88))
        case .secondary:
            if isPressed { return .white.opacity(0.14) }
            return isLit ? theme.accent.opacity(0.14) : .white.opacity(0.065)
        }
    }
}

// MARK: - Menu bar content (unchanged)

// MARK: - MarkdownUI Theme

extension MarkdownUI.Theme {
    @MainActor static let completionCard = Theme()
        .text {
            // Read at a glance from a metre away, on a dark panel, often while
            // the user is mid-thought in another window.
            ForegroundColor(.white.opacity(0.96))
            FontSize(14)
            FontWeight(.medium)
        }
        .link {
            ForegroundColor(.blue)
        }
        .strong {
            FontWeight(.bold)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(12.5)
            ForegroundColor(.white.opacity(0.88))
            BackgroundColor(.white.opacity(0.08))
        }
        .codeBlock { configuration in
            configuration.label
                .markdownTextStyle {
                    FontFamilyVariant(.monospaced)
                    FontSize(12.5)
                    ForegroundColor(.white.opacity(0.88))
                }
                .padding(10)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .heading1 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontSize(16)
                    FontWeight(.bold)
                    ForegroundColor(.white.opacity(0.88))
                }
                .markdownMargin(top: 8, bottom: 4)
        }
        .heading2 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontSize(15)
                    FontWeight(.bold)
                    ForegroundColor(.white.opacity(0.88))
                }
                .markdownMargin(top: 8, bottom: 4)
        }
        .heading3 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontSize(14)
                    FontWeight(.semibold)
                    ForegroundColor(.white.opacity(0.88))
                }
                .markdownMargin(top: 6, bottom: 2)
        }
        .blockquote { configuration in
            configuration.label
                .markdownTextStyle {
                    ForegroundColor(.white.opacity(0.6))
                    FontSize(13.5)
                }
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 3)
                }
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: 2, bottom: 2)
        }
        .table { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .markdownTableBorderStyle(.init(.allBorders, color: .white.opacity(0.15), strokeStyle: .init(lineWidth: 1)))
                .markdownTableBackgroundStyle(
                    .alternatingRows(Color.white.opacity(0.04), Color.white.opacity(0.08))
                )
                .markdownMargin(top: 4, bottom: 8)
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 {
                        FontWeight(.semibold)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .relativeLineSpacing(.em(0.25))
        }
}

private struct DismissButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.islandText(size: 12))
                .foregroundStyle(.white.opacity(isHovered ? 0.8 : 0.4))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
