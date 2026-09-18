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

            Text(lang.t("island.sessionList.title").uppercased())
                .font(.islandMono(size: 10.5, weight: .semibold))
                .tracking(1.4)
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
            ForEach(sections) { section in
                if showsSections {
                    sectionHeader(section)
                }

                ForEach(section.items) { item in
                    SessionListLivePreviewRow(
                        item: item,
                        indicator: indicator,
                        sideInset: sideInset,
                        lang: lang
                    )
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
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                if indicator != .tint {
                    indicatorView
                }

                VStack(alignment: .leading, spacing: 3) {
                    titleLine

                    if let prompt = item.prompt {
                        Text(prompt)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(V6Palette.paper.opacity(item.phase == .idle ? 0.34 : 0.52))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 10)

                HStack(spacing: 6) {
                    agentChip
                    sideBadge(item.terminal)
                    Text(item.age)
                        .font(.islandMono(size: 10.5, weight: .medium))
                        .foregroundStyle(V6Palette.paper.opacity(item.phase == .idle ? 0.32 : 0.45))
                        .frame(minWidth: 30, alignment: .trailing)

                    Image(systemName: item.phase == .idle ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(V6Palette.paper.opacity(item.phase == .idle ? 0.42 : 0.68))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(V6Palette.paper.opacity(item.phase == .idle ? 0.02 : 0.045))
                        )
                }
            }
            .padding(.horizontal, rowLeadingPadding)
            .padding(.vertical, 11)
            .background(rowFill)

            if item.phase != .idle {
                detailPreview
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(V6Palette.paper.opacity(0.04))
                .frame(height: 1)
        }
        .overlay(alignment: .leading) {
            if indicator == .bar {
                IslandThemes.current.shape(cornerRadius: 999)
                    .fill(tint)
                    .frame(width: 3)
                    .padding(.vertical, 8)
                    .padding(.leading, 14)
            }
        }
        .opacity(item.phase == .idle ? 0.74 : 1)
    }

    private var titleLine: some View {
        HStack(spacing: 0) {
            Text(item.project)
                .fontWeight(.semibold)
                .foregroundStyle(projectColor)
            if let branch = item.branch {
                Text(" (\(branch))")
                    .foregroundStyle(V6Palette.paper.opacity(0.55))
            }
            Text(" · ")
                .foregroundStyle(V6Palette.paper.opacity(0.22))
            Text(item.detail)
                .foregroundStyle(V6Palette.paper.opacity(0.7))
        }
        .font(.system(size: 13, weight: .medium))
        .lineLimit(1)
    }

    private var agentChip: some View {
        Text(item.agentShort)
            .font(.islandMono(size: 10.5, weight: .semibold))
            .foregroundStyle(item.agentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(item.agentColor.opacity(0.13), in: Capsule())
            .overlay(Capsule().stroke(item.agentColor.opacity(0.35), lineWidth: 1))
    }

    private func sideBadge(_ text: String) -> some View {
        Text(text)
            .font(.islandMono(size: 10.5, weight: .medium))
            .foregroundStyle(V6Palette.paper.opacity(0.7))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(V6Palette.paper.opacity(0.06), in: Capsule())
    }

    private var detailPreview: some View {
        VStack(alignment: .leading, spacing: 7) {
            switch item.phase {
            case .approval:
                Text(lang.t("approval.toolPermissionRequested"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(V6Palette.paper.opacity(0.86))
                Text(lang.t("settings.appearance.preview.permissionBody"))
                    .font(.islandMono(size: 11.5, weight: .semibold))
                    .foregroundStyle(V6Palette.paper.opacity(0.78))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(V6Palette.paper.opacity(0.045), in: IslandThemes.current.shape(cornerRadius: 7))
            case .answer:
                Text(lang.t("settings.appearance.preview.pickOrTypeAnswer"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(V6Palette.paper.opacity(0.82))
            case .running:
                Text(item.detail)
                    .font(.islandMono(size: 11.5, weight: .semibold))
                    .foregroundStyle(V6Palette.paper.opacity(0.78))
            case .done:
                Text(lang.t("settings.appearance.preview.replyAvailable"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(V6Palette.paper.opacity(0.82))
            case .idle:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, detailLeadingPadding)
        .padding(.trailing, sideInset)
        .padding(.bottom, 12)
        .background(V6Palette.paper.opacity(0.015))
    }

    @ViewBuilder
    private var indicatorView: some View {
        switch indicator {
        case .animatedDot:
            Circle()
                .fill(tint)
                .frame(width: 9, height: 9)
                .shadow(color: tint.opacity(item.phase == .idle ? 0 : 0.44), radius: 5)
                .frame(width: 20, height: 20)
        case .bar:
            EmptyView()
        case .glyph:
            glyphView
                .frame(width: 20, height: 20)
        case .tint:
            EmptyView()
        }
    }

    private var rowFill: Color {
        guard indicator == .tint else { return Color.clear }
        return tint.opacity(item.phase == .idle ? 0.015 : 0.045)
    }

    @ViewBuilder
    private var glyphView: some View {
        switch item.phase {
        case .idle:
            Circle()
                .fill(V6Palette.paper.opacity(0.3))
                .frame(width: 4, height: 4)
        case .running:
            UnifiedBars(mode: .running, size: 16, tint: tint)
        case .approval, .answer:
            UnifiedBars(mode: .waiting, size: 16, tint: tint)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
        }
    }

    private var projectColor: Color {
        indicator == .tint && item.phase != .idle ? tint : V6Palette.paper.opacity(item.phase == .idle ? 0.72 : 0.92)
    }

    private var tint: Color {
        item.phase.tint
    }

    private var rowLeadingPadding: CGFloat {
        switch indicator {
        case .bar: max(28, sideInset)
        case .tint: sideInset
        case .animatedDot, .glyph: sideInset
        }
    }

    private var detailLeadingPadding: CGFloat {
        switch indicator {
        case .bar: max(28, sideInset)
        case .tint: sideInset
        case .animatedDot, .glyph: sideInset + 30
        }
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
