import OpenIslandCore
import SwiftUI

struct SessionPreviewSection: Identifiable {
    let id: String
    let title: String
    let items: [SessionPreviewItem]
}

struct SessionPreviewItem: Identifiable {
    enum Phase {
        case approval
        case answer
        case running
        case done
        case idle
    }

    let id: String
    let title: String
    let detail: String
    let agent: String
    let agentShort: String
    let agentColor: Color
    let project: String
    let branch: String?
    let prompt: String?
    let terminal: String
    let age: String
    let phase: Phase
    let attentionRank: Int
    let updatedRank: Int
}

/// The five made-up sessions the list preview is drawn from, grouped and
/// sorted the way the preferences being edited would group and sort them.
struct SessionListPreviewFixture {
    let group: IslandSessionGroup
    let sort: IslandSessionSort
    /// What the finished session's age reads as — the done-timeout choice.
    let doneAge: String
    let lang: LanguageManager

    var sections: [SessionPreviewSection] {
        let items = sortedItems

        switch group {
        case .none:
            return [
                SessionPreviewSection(
                    id: "all",
                    title: lang.t("settings.appearance.sessionGroup.none"),
                    items: items
                )
            ]
        case .state:
            let groups: [(String, String, (SessionPreviewItem) -> Bool)] = [
                ("approval", lang.t("island.section.needsApproval"), { $0.phase == .approval }),
                ("answer", lang.t("island.section.needsAnswer"), { $0.phase == .answer }),
                ("running", lang.t("island.section.inProgress"), { $0.phase == .running }),
                ("done", lang.t("island.section.justDone"), { $0.phase == .done }),
                ("idle", lang.t("island.section.idle"), { $0.phase == .idle }),
            ]
            return groups.compactMap { id, title, include in
                let groupItems = items.filter(include)
                guard !groupItems.isEmpty else { return nil }
                return SessionPreviewSection(id: id, title: title, items: groupItems)
            }
        case .agent:
            let groups = ["Codex", "Claude", "Cursor", "Gemini"]
            return groups.compactMap { agent in
                let groupItems = items.filter { $0.agent == agent }
                guard !groupItems.isEmpty else { return nil }
                return SessionPreviewSection(id: agent, title: agent, items: groupItems)
            }
        case .project:
            let groups = ["open-island", "website", "docs"]
            return groups.compactMap { project in
                let groupItems = items.filter { $0.project == project }
                guard !groupItems.isEmpty else { return nil }
                return SessionPreviewSection(id: project, title: project, items: groupItems)
            }
        }
    }

    private var sortedItems: [SessionPreviewItem] {
        switch sort {
        case .attention:
            return allItems.sorted { lhs, rhs in
                if lhs.attentionRank == rhs.attentionRank {
                    return lhs.updatedRank < rhs.updatedRank
                }
                return lhs.attentionRank < rhs.attentionRank
            }
        case .lastUpdate:
            return allItems.sorted { $0.updatedRank < $1.updatedRank }
        }
    }

    private var allItems: [SessionPreviewItem] {
        [
            .init(
                id: "approval",
                title: "Codex · open-island",
                detail: lang.t("settings.appearance.preview.approveShellCommand"),
                agent: "Codex",
                agentShort: "codex",
                agentColor: Color(hex: AgentTool.codex.brandColorHex) ?? Color(red: 0.55, green: 0.72, blue: 1.0),
                project: "open-island",
                branch: "v8-design",
                prompt: lang.t("settings.appearance.preview.promptImplementPlan"),
                terminal: "Ghostty",
                age: "now",
                phase: .approval,
                attentionRank: 0,
                updatedRank: 2
            ),
            .init(
                id: "answer",
                title: "Claude · open-island",
                detail: lang.t("settings.appearance.preview.waitingForAnswer"),
                agent: "Claude",
                agentShort: "claude",
                agentColor: Color(hex: AgentTool.claudeCode.brandColorHex) ?? Color(red: 0.9, green: 0.55, blue: 0.34),
                project: "open-island",
                branch: "main",
                prompt: lang.t("settings.appearance.preview.promptChooseNotificationCopy"),
                terminal: "Ghostty",
                age: "1m",
                phase: .answer,
                attentionRank: 1,
                updatedRank: 3
            ),
            .init(
                id: "running",
                title: "Cursor · website",
                detail: lang.t("settings.appearance.preview.editingSessionListPreview"),
                agent: "Cursor",
                agentShort: "cursor",
                agentColor: Color(hex: AgentTool.cursor.brandColorHex) ?? Color(red: 0.62, green: 0.66, blue: 1.0),
                project: "website",
                branch: "main",
                prompt: lang.t("settings.appearance.preview.promptTightenSettingsUI"),
                terminal: "Cursor",
                age: "2m",
                phase: .running,
                attentionRank: 2,
                updatedRank: 0
            ),
            .init(
                id: "done",
                title: "Gemini · docs",
                detail: lang.t("settings.appearance.preview.replyAvailable"),
                agent: "Gemini",
                agentShort: "gemini",
                agentColor: Color(hex: AgentTool.geminiCLI.brandColorHex) ?? Color(red: 0.45, green: 0.78, blue: 1.0),
                project: "docs",
                branch: "main",
                prompt: lang.t("settings.appearance.preview.promptSummarizeDesignBundle"),
                terminal: "WezTerm",
                age: doneAge,
                phase: .done,
                attentionRank: 3,
                updatedRank: 1
            ),
            .init(
                id: "idle",
                title: "Codex · open-island",
                detail: lang.t("settings.appearance.preview.completedEarlier"),
                agent: "Codex",
                agentShort: "codex",
                agentColor: Color(hex: AgentTool.codex.brandColorHex) ?? Color(red: 0.55, green: 0.72, blue: 1.0),
                project: "open-island",
                branch: nil,
                prompt: nil,
                terminal: "Ghostty",
                age: lang.t("island.sessionOverview.idle"),
                phase: .idle,
                attentionRank: 4,
                updatedRank: 4
            ),
        ]
    }
}

struct SessionListPanelPreview: View {
    let sections: [SessionPreviewSection]
    let showsSections: Bool
    let indicator: IslandSessionStateIndicator
    let profile: IslandAppearanceDisplayProfile
    let lang: LanguageManager

    private var items: [SessionPreviewItem] {
        sections.flatMap(\.items)
    }

    private var waitingCount: Int {
        items.filter { $0.phase == .approval || $0.phase == .answer }.count
    }

    private var runningCount: Int {
        items.filter { $0.phase == .running }.count
    }

    private var doneCount: Int {
        items.filter { $0.phase == .done }.count
    }

    private var idleCount: Int {
        items.filter { $0.phase == .idle }.count
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            panel(width: preferredPanelWidth)
            panel(width: 500)
            panel(width: 460)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var preferredPanelWidth: CGFloat {
        profile == .notch ? 540 : 520
    }

    private func panel(width: CGFloat) -> some View {
        ZStack(alignment: .top) {
            surfaceShape
                .fill(V6Palette.ink)
                .shadow(color: .black.opacity(0.36), radius: 22, y: 12)

            VStack(spacing: 0) {
                panelHead
                listBody
                panelFoot
            }
            .clipShape(surfaceShape)
        }
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var surfaceShape: OpenedIslandSurfaceShape {
        OpenedIslandSurfaceShape(topProfile: profile == .notch ? .notch : .floatingPill)
    }

    private var sideInset: CGFloat {
        profile == .notch ? 46 : 16
    }

    private var panelHead: some View {
        HStack(spacing: 8) {
            UnifiedBars(mode: .waiting, size: 22)
                .frame(width: 24, height: 24)

            Text(lang.t("island.sessionList.title"))
                .font(.islandMono(size: 10.5, weight: .semibold))

                .foregroundStyle(V6Palette.paper.opacity(0.55))

            ViewThatFits(in: .horizontal) {
                previewSessionOverview(compact: false)
                previewSessionOverview(compact: true)
            }

            Spacer(minLength: 0)

            previewHeaderButton(systemName: "gearshape.fill")
        }
        .padding(.leading, sideInset)
        .padding(.trailing, sideInset)
        .frame(height: 42)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(V6Palette.paper.opacity(0.05))
                .frame(height: 1)
        }
    }

    private func previewHeaderButton(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(V6Palette.paper.opacity(0.62))
            .frame(width: 22, height: 22)
            .background(V6Palette.paper.opacity(0.08), in: Circle())
    }

    private func previewSessionOverview(compact: Bool) -> some View {
        HStack(spacing: compact ? 7 : 9) {
            previewSessionOverviewMetric(
                count: items.count,
                title: lang.t("island.sessionOverview.total"),
                compactTitle: "",
                tint: nil,
                compact: compact
            )
            if waitingCount > 0 {
                previewSessionOverviewMetric(
                    count: waitingCount,
                    title: lang.t("island.sessionOverview.waiting"),
                    compactTitle: lang.t("island.sessionOverview.waitingCompact"),
                    tint: IslandDesignPalette.Status.waitingAggregate,
                    compact: compact
                )
            }
            if runningCount > 0 {
                previewSessionOverviewMetric(
                    count: runningCount,
                    title: lang.t("island.sessionOverview.running"),
                    compactTitle: lang.t("island.sessionOverview.runningCompact"),
                    tint: IslandDesignPalette.Status.running,
                    compact: compact
                )
            }
            if doneCount > 0 {
                previewSessionOverviewMetric(
                    count: doneCount,
                    title: lang.t("island.sessionOverview.done"),
                    compactTitle: lang.t("island.sessionOverview.done"),
                    tint: IslandDesignPalette.Status.completed,
                    compact: compact
                )
            }
            if idleCount > 0 {
                previewSessionOverviewMetric(
                    count: idleCount,
                    title: lang.t("island.sessionOverview.idle"),
                    compactTitle: lang.t("island.sessionOverview.idle"),
                    tint: IslandDesignPalette.Status.idle,
                    compact: compact
                )
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func previewSessionOverviewMetric(
        count: Int,
        title: String,
        compactTitle: String,
        tint: Color?,
        compact: Bool
    ) -> some View {
        HStack(spacing: 4) {
            if let tint {
                Circle()
                    .fill(tint)
                    .frame(width: 5.5, height: 5.5)
            }

            let label = title == "total"
                ? (compact ? "\(count)" : "\(count) \(title)")
                : "\(count) \(compact ? compactTitle : title)"

            Text(label)
                .font(.islandMono(size: 10.5, weight: .semibold))
                .foregroundStyle(tint == nil ? V6Palette.paper.opacity(0.34) : V6Palette.paper.opacity(0.48))
        }
    }

    private var listBody: some View {
        VStack(spacing: 0) {
            ForEach(IslandSessionPriority.allCases) { priority in
                let matching = sections.compactMap { section -> SessionPreviewSection? in
                    let items = section.items.filter { priority.contains($0.previewSession) }
                    return items.isEmpty ? nil : SessionPreviewSection(id: section.id, title: section.title, items: items)
                }
                if !matching.isEmpty {
                    Text(priority.title)
                        .font(.islandDecision(size: 12, weight: .semibold))
                        .foregroundStyle(V6Palette.paper.opacity(0.86))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, sideInset).padding(.top, 12).padding(.bottom, 6)
                }
                ForEach(matching) { section in
                    if showsSections { sectionHeader(section) }
                    ForEach(section.items) { item in
                        SessionListLivePreviewRow(item: item, indicator: indicator, sideInset: sideInset, lang: lang)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ section: SessionPreviewSection) -> some View {
        HStack(spacing: 8) {
            sectionDot(for: section)
            Text(section.title.uppercased())
                .font(.islandMono(size: 10.5, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(V6Palette.paper.opacity(0.7))
            Text("\(section.items.count)")
                .font(.islandMono(size: 10.5, weight: .medium))
                .foregroundStyle(V6Palette.paper.opacity(0.4))
            Spacer(minLength: 0)
        }
        .padding(.leading, sideInset)
        .padding(.trailing, sideInset)
        .padding(.top, 9)
        .padding(.bottom, 6)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(V6Palette.paper.opacity(0.05))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func sectionDot(for section: SessionPreviewSection) -> some View {
        Circle()
            .fill(section.items.first?.phase.tint ?? V6Palette.paper.opacity(0.35))
            .frame(width: 7, height: 7)
    }

    private var panelFoot: some View {
        Color.clear
            .frame(height: 10)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(V6Palette.paper.opacity(0.05))
                .frame(height: 1)
        }
    }
}

struct SessionListLivePreviewRow: View {
    let item: SessionPreviewItem
    let indicator: IslandSessionStateIndicator
    let sideInset: CGFloat
    let lang: LanguageManager

    var body: some View {
        let session = item.previewSession
        IslandSessionRow(session: session, referenceDate: .now, stateIndicator: indicator,
            isActionable: session.phase.requiresAttention, useDrawingGroup: false, isInteractive: false,
            sideInset: sideInset, lang: lang, onJump: {})
            .allowsHitTesting(false)
    }
}

extension SessionPreviewItem {
    var previewSession: AgentSession {
        let tool: AgentTool = switch agentShort {
        case "claude": .claudeCode
        case "cursor": .cursor
        case "gemini": .geminiCLI
        default: .codex
        }
        let nativePhase: SessionPhase = switch phase {
        case .approval: .waitingForApproval
        case .answer: .waitingForAnswer
        case .running: .running
        case .done, .idle: .completed
        }
        var session = AgentSession(id: "preview-" + id, title: prompt ?? title, tool: tool,
            origin: .demo, attachmentState: .attached, phase: nativePhase, summary: detail,
            updatedAt: .now.addingTimeInterval(phase == .idle ? -7200 : -60),
            jumpTarget: JumpTarget(terminalApp: terminal, workspaceName: project, paneTitle: title))
        if phase == .approval {
            session.permissionRequest = PermissionRequest(title: LanguageManager.shared.t("decision.approval.title"), summary: detail,
                affectedPath: project, primaryActionTitle: LanguageManager.shared.t("decision.allowOnce"), secondaryActionTitle: LanguageManager.shared.t("decision.deny"), toolName: "Bash")
        } else if phase == .answer {
            session.questionPrompt = QuestionPrompt(title: detail, questions: [QuestionPromptItem(
                question: prompt ?? detail, header: LanguageManager.shared.t("decision.question.title"), options: [QuestionOption(label: LanguageManager.shared.t("decision.continue")),
                    QuestionOption(label: LanguageManager.shared.t("decision.other"), allowsFreeform: true)])])
        }
        return session
    }
}

private extension SessionPreviewItem.Phase {
    @MainActor
    var tint: Color {
        switch self {
        case .approval:
            IslandDesignPalette.Status.waitingForApproval
        case .answer:
            IslandDesignPalette.Status.waitingForAnswer
        case .running:
            IslandDesignPalette.Status.running
        case .done:
            IslandDesignPalette.Status.completed
        case .idle:
            IslandDesignPalette.Status.idle
        }
    }
}
