import SwiftUI
import OpenIslandCore

extension IslandSessionRow {
    var agentBadge: some View {
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

    func sideBadge(_ title: String) -> some View {
        Text(title)
            .font(.islandMono(size: 10.5, weight: .medium))
            .lineLimit(1)
            .truncationMode(.tail)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(V6Palette.paper.opacity(presentation == .notification ? 0.52 : 0.7))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(V6Palette.paper.opacity(presentation == .notification ? 0.045 : 0.06), in: Capsule())
    }

    var summaryPromptLineText: String? {
        if presentation == .notification {
            if session.phase == .completed {
                return notificationCompletedPromptLineText
            }
            return session.notificationHeaderPromptLineText
        }

        return session.spotlightPromptLineText ?? expandedPromptLineText
    }

    var summaryHeadlineText: String {
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

    var rowLeadingInset: CGFloat {
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

    var detailLeadingInset: CGFloat {
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

    var showsLeadingGlyphPair: Bool {
        presentation == .list && stateIndicator != .tint && stateIndicator != .bar
    }

    var showsLeadingStatusIndicator: Bool {
        false
    }

    var showsLeadingStatusBar: Bool {
        presentation == .list && stateIndicator == .bar
    }

    var summaryTitleFont: Font {
        .system(size: presentation == .notification ? 13.2 : (isActionable ? 13.8 : 13.2), weight: .semibold)
    }

    func summaryPromptColor(for presence: IslandSessionPresence) -> Color {
        if presentation == .notification {
            return V6Palette.paper.opacity(session.phase == .completed ? 0.38 : 0.46)
        }

        return V6Palette.paper.opacity(presence == .inactive ? 0.34 : 0.52)
    }

    func summaryAgeColor(for presence: IslandSessionPresence) -> Color {
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

    func titleColor(for presence: IslandSessionPresence) -> Color {
        if stateIndicator == .tint && presence != .inactive {
            return statusTint(for: presence)
        }

        if presentation == .notification, session.phase == .completed {
            return V6Palette.paper.opacity(0.78)
        }

        return headlineColor(for: presence)
    }

    private var actionableBorderColor: Color {
        if isActionable {
            return actionableStatusTint.opacity(isHighlighted ? 0.45 : 0.28)
        }
        return isHighlighted ? V6Palette.paper.opacity(0.24) : V6Palette.paper.opacity(0.04)
    }

    private var actionableStatusTint: Color {
        IslandDesignPalette.Status.tint(for: session.phase)
    }

    var shouldShowEmbeddedDetailBody: Bool {
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
    var embeddedDetailBody: some View {
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
                    .foregroundStyle(V6Palette.paper.opacity(0.82))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        IslandThemes.current.shape(cornerRadius: 7)
                            .fill(V6Palette.paper.opacity(0.045))
                    )
                    .overlay(
                        IslandThemes.current.shape(cornerRadius: 7)
                            .strokeBorder(V6Palette.paper.opacity(0.06))
                    )
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    @ViewBuilder
    func statusIndicator(for presence: IslandSessionPresence) -> some View {
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

    func rowFillColor(for presence: IslandSessionPresence) -> Color {
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

    var allowsRowHoverHighlight: Bool {
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

    var resolvedActivityLine: IslandActivityLine? {
        session.spotlightActivityLine ?? expandedActivityLine
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
        .background(V6Palette.paper.opacity(0.12), in: Capsule())
    }

    private func headlineColor(for presence: IslandSessionPresence) -> Color {
        presence == .inactive ? V6Palette.paper.opacity(0.78) : V6Palette.paper
    }

    private func badgeTextColor(for presence: IslandSessionPresence) -> Color {
        presence == .inactive ? V6Palette.paper.opacity(0.42) : V6Palette.paper.opacity(0.56)
    }

    func statusTint(for presence: IslandSessionPresence) -> Color {
        IslandDesignPalette.Status.tint(for: session.phase, presence: presence)
    }

    func activityColor(for presence: IslandSessionPresence) -> Color {
        switch session.spotlightActivityTone {
        case .attention:
            IslandDesignPalette.Status.tint(for: session.phase)
        case .live:
            statusTint(for: presence)
        case .idle:
            V6Palette.paper.opacity(0.46)
        case .ready:
            presence == .inactive ? V6Palette.paper.opacity(0.46) : statusTint(for: presence)
        }
    }

}
