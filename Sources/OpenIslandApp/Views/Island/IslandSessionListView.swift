import SwiftUI
import OpenIslandCore

private struct NotificationContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SessionOverviewItem: Identifiable {
    let id: String
    let title: String
    let compactTitle: String
    let count: Int
    let tint: Color?
}

extension IslandPanelView {
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

    var sessionList: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let referenceDate = context.date

            if isNotificationMode {
                // Sizes itself from its content, and scrolls once that content
                // outgrows what the panel can be. The panel's height comes from
                // an estimate first and a measurement second; when the two
                // disagree the last control in the card used to end up outside
                // the window with no way to reach it. Now the worst case is a
                // scroll rather than something unreachable.
                AutoHeightScrollView(maxHeight: IslandChromeMetrics.notificationContentMaxHeight) {
                    sessionListContent(referenceDate: referenceDate)
                }
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
                    .fill(V6Palette.paper.opacity(0.06))
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
                    onAutoApprove: { model.autoAnswerSessions(matching: $0) },
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
                            .foregroundStyle(V6Palette.paper.opacity(0.36))
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
                    onAutoApprove: { model.autoAnswerSessions(matching: $0) },
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
                    onAutoApprove: { model.autoAnswerSessions(matching: $0) },
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
                .fill(V6Palette.paper.opacity(0.055))
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
        .background(V6Palette.paper.opacity(0.008))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(V6Palette.paper.opacity(0.055))
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

}
