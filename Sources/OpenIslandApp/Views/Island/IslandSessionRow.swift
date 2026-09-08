import SwiftUI
import OpenIslandCore

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

// MARK: - Session row (opened state)

enum IslandSessionRowPresentation {
    case list
    case notification
}

struct IslandSessionRow: View {
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
    /// Adds a rule that answers this kind of session's permission requests.
    var onAutoApprove: ((AutoResponseRule) -> Void)?
    var agentIconStyle: AgentIconStyle = .pixel
    /// Non-nil only while the shortcut modifier is held.
    var shortcutHint: ShortcutSettings?
    /// Draws the switcher's ring when this row is the one selected.
    var isSwitcherHighlighted = false
    /// True for the row a hand gesture pointed at when it opened the
    /// island — draws a `saoOutline` ring for the first 1.2s the row exists.
    var isGestureHighlighted = false
    /// Prefer a name derived from the first prompt over the workspace name.
    var usesAutoNaming = false

    @State var isHighlighted = false
    @State var detailOverride: Bool?
    @State var replyText: String = ""
    @State private var showsGestureRing = true
    /// Invalidates a pending hide from a stale arming — without this, a ring
    /// armed for one session could still fire its hide after the row was
    /// reused for a different, freshly-armed one.
    @State private var gestureRingGeneration = 0

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
                        // `IslandTransition.modal` scales visually but never
                        // shrinks the layout height it reserves, so inside
                        // this row's scroll view the rest of the list jumped
                        // to its final position the instant this appeared —
                        // only the scale animated, not the space around it.
                        // A plain fade has no such mismatch to expose.
                        .transition(.opacity)
                }
            }
        }
        .background(rowFillColor(for: presence))
        .overlay(
            IslandThemes.current.shape(cornerRadius: 8)
                .strokeBorder(V6Palette.paper.opacity(isSwitcherHighlighted ? 0.55 : 0), lineWidth: 1.5)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(V6Palette.paper.opacity(0.045))
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
            } else if isHighlighted, presentation == .list {
                // The hover/selection mark for the default (dot) indicator
                // style: a thin accent bar rather than the state dot growing,
                // since the dot already carries the session's own status.
                Rectangle()
                    .fill(SAOGrammar.Palette.accentOrange)
                    .frame(width: 3)
                    .padding(.vertical, showsDetail ? 10 : 8)
            }
        }
        .opacity(isStaleCompleted ? 0.7 : 1)
        .saoOutline(IslandThemes.current.shape(cornerRadius: 8), when: isGestureHighlighted && showsGestureRing)
        // The drawing group flattens the row into a bitmap, which is why it is
        // off while hovering: a cached row cannot show a glow that changes.
        .modifier(ConditionalDrawingGroup(enabled: useDrawingGroup && !isActionable && !isHighlighted))
        .animation(.easeInOut(duration: 0.15), value: isHighlighted)
        // A session that changes state should be seen changing, not found
        // already changed the next time you look at the panel.
        .animation(IslandMotion.rowPhase, value: session.phase)
        .onAppear { armGestureRingIfHighlighted() }
        // List rows get reused for a different session at the same scroll
        // position without a fresh `onAppear` — without this, a row that
        // already hid its ring for a past session stayed hidden forever for
        // whichever session landed on it next.
        .onChange(of: session.id) { _, _ in
            showsGestureRing = true
            armGestureRingIfHighlighted()
        }
        .onChange(of: isGestureHighlighted) { _, _ in
            showsGestureRing = true
            armGestureRingIfHighlighted()
        }
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

    /// Schedules the ring's own 1.2s hide, only while this row is actually
    /// the one a gesture pointed at. Each call retires any hide scheduled by
    /// an earlier call, so a row recycled mid-countdown for a new highlight
    /// isn't hidden early by the old session's timer.
    private func armGestureRingIfHighlighted() {
        guard isGestureHighlighted else { return }
        gestureRingGeneration &+= 1
        let generation = gestureRingGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard generation == gestureRingGeneration else { return }
            showsGestureRing = false
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
        if onAutoApprove != nil, let directory = session.jumpTarget?.workingDirectory, !directory.isEmpty {
            Button(
                LanguageManager.shared.t("island.session.autoApproveFolder")
                    .replacingOccurrences(of: "{name}", with: (directory as NSString).lastPathComponent)
            ) {
                onAutoApprove?(
                    AutoResponseRule(
                        field: .workingDirectory,
                        match: .equals,
                        pattern: directory,
                        behavior: .allowOnce
                    )
                )
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
                    iconStyle: agentIconStyle
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
                            .foregroundStyle(V6Palette.paper.opacity(0.8))
                            .lineLimit(1)
                        if let desc = sub.taskDescription {
                            Text("(\(desc))")
                                .font(.islandText(size: 10.5))
                                .foregroundStyle(V6Palette.paper.opacity(0.5))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if sub.summary != nil {
                            Text(lang.t("subagents.completed"))
                                .font(.islandText(size: 10, weight: .medium))
                                .foregroundStyle(V6Palette.paper.opacity(0.4))
                        } else if let started = sub.startedAt {
                            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                                Text(subagentElapsed(since: started, at: timeline.date))
                                    .font(.islandText(size: 10, weight: .medium))
                                    .foregroundStyle(V6Palette.paper.opacity(0.4))
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
                    .foregroundStyle(V6Palette.paper.opacity(0.45))
                ForEach(tasks) { task in
                    HStack(spacing: 5) {
                        taskStatusIcon(task.status)
                        Text(task.title)
                            .font(.islandText(size: 10.5, weight: .medium))
                            .foregroundStyle(task.status == .completed
                                ? V6Palette.paper.opacity(0.4)
                                : V6Palette.paper.opacity(0.7))
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

    @ViewBuilder
    var actionableBody: some View {
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
                .foregroundStyle(V6Palette.paper.opacity(0.35))
        case .inProgress:
            Circle()
                .fill(IslandDesignPalette.Status.running)
                .frame(width: 6, height: 6)
        case .pending:
            Circle()
                .strokeBorder(V6Palette.paper.opacity(0.3), lineWidth: 1)
                .frame(width: 6, height: 6)
        }
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
                .foregroundStyle(isOpen || isHighlighted ? V6Palette.paper.opacity(0.68) : V6Palette.paper.opacity(0.42))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(V6Palette.paper.opacity(detailToggleFillOpacity(isOpen: isOpen)))
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
}
