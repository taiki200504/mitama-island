import SwiftUI
import OpenIslandCore

/// The display pane's appearance group: what the closed island and the session
/// list show, per display profile, with a live preview of each.
///
/// Was the separate appearance tab; it now sits inside the display pane so
/// "where the island is" and "what it looks like" are set in one place.
struct DisplayIslandSection: View {
    var model: AppModel
    @State private var previewMode: UnifiedBars.Mode = .idle
    @State private var previewAutoCycle: Bool = true

    private static let autoCycleOrder: [UnifiedBars.Mode] = [.idle, .running, .waiting]
    private static let autoCycleInterval: TimeInterval = 2.0

    private var lang: LanguageManager { model.lang }
    private var editingProfile: IslandAppearanceDisplayProfile { model.appearanceSettingsProfile }
    private var editingPreferences: IslandAppearancePreferences {
        model.appearancePreferences(for: editingProfile)
    }
    private var previewLayout: V6ClosedLayout {
        editingProfile == .notch ? .macbook : .external
    }

    var body: some View {
        Section(lang.t("settings.display.section.appearance")) {
            VStack(alignment: .leading, spacing: 32) {
                displayProfilePart
                notchPersonalizationPart
                sessionListPersonalizationPart
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Display profile

    private var displayProfilePart: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: lang.t("settings.appearance.profile.title"),
                note: lang.t("settings.appearance.profile.note")
            )

            HStack(spacing: 12) {
                displayProfileCard(
                    .topBar,
                    icon: "display",
                    title: lang.t("settings.appearance.profile.external.title"),
                    note: lang.t("settings.appearance.profile.external.note")
                )
                displayProfileCard(
                    .notch,
                    icon: "laptopcomputer",
                    title: lang.t("settings.appearance.profile.macbook.title"),
                    note: lang.t("settings.appearance.profile.macbook.note")
                )
            }
        }
    }

    private func displayProfileCard(
        _ profile: IslandAppearanceDisplayProfile,
        icon: String,
        title: String,
        note: String
    ) -> some View {
        let selected = editingProfile == profile
        return Button {
            model.appearanceSettingsProfile = profile
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(selected ? V6Palette.paper : V6Palette.paper.opacity(0.55))
                    .frame(width: 34, height: 34)
                    .background(
                        IslandThemes.current.shape(cornerRadius: 8)
                            .fill(V6Palette.paper.opacity(selected ? 0.11 : 0.05))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(V6Palette.paper.opacity(0.94))
                    Text(note)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(V6Palette.paper.opacity(0.42))
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(V6Palette.paper.opacity(0.9))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                IslandThemes.current.shape(cornerRadius: 12)
                    .fill(V6Palette.paper.opacity(selected ? 0.075 : 0.025))
            )
            .overlay(
                IslandThemes.current.shape(cornerRadius: 12)
                    .stroke(selected ? V6Palette.paper.opacity(0.86) : V6Palette.paper.opacity(0.08), lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Notch part

    private var notchPersonalizationPart: some View {
        VStack(alignment: .leading, spacing: 18) {
            partHeader(title: lang.t("settings.appearance.notchPart.title"))
            previewSection
            rightSlotSection
            centerLabelSection
        }
    }

    // MARK: - Session list part

    private var sessionListPersonalizationPart: some View {
        VStack(alignment: .leading, spacing: 18) {
            partHeader(title: lang.t("settings.appearance.sessionListPart.title"))
            sessionListPreviewSection
            usageDisplaySection
            stateIndicatorSection
            sessionGroupSection
            sessionSortSection
            staleThresholdSection
        }
    }

    // MARK: - Notch preview

    @ViewBuilder
    private var previewSection: some View {
        sectionHeader(title: lang.t("settings.appearance.preview"), note: nil)

        SettingsPreviewStage(contentTopPadding: 16, contentBottomPadding: 18) {
            VStack(spacing: 14) {
                previewStage
                previewControls
            }
            .padding(.horizontal, 18)
        }
    }

    private var previewStage: some View {
        let physicalNotchW: CGFloat = 180
        let pillHeight: CGFloat = 32

        return ZStack(alignment: .top) {
            if previewLayout == .macbook {
                // Physical hardware notch mock — pinned to the TOP of the
                // frame, same as the real physical cutout would sit at the
                // top of the display.
                V6ClosedPillShape()
                    .fill(Color.black)
                    .frame(width: physicalNotchW, height: pillHeight)
            }

            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                IslandPreviewPill(
                    mode: previewMode,
                    label: previewLabel,
                    rightSlot: previewRightContent,
                    layout: previewLayout,
                    physicalNotchWidth: physicalNotchW,
                    now: context.date
                )
            }
        }
        .frame(height: pillHeight)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var previewControls: some View {
        HStack(spacing: 10) {
            // Auto-cycle toggle (default on — drives the state chips).
            monoChip(
                title: previewAutoCycle
                    ? lang.t("settings.appearance.state.auto.on")
                    : lang.t("settings.appearance.state.auto.off"),
                selected: previewAutoCycle
            ) {
                previewAutoCycle.toggle()
            }

            // Manual state chips — selecting one turns off auto-cycle.
            ForEach([UnifiedBars.Mode.idle, .running, .waiting], id: \.self) { mode in
                monoChip(title: title(for: mode), selected: !previewAutoCycle && previewMode == mode) {
                    previewAutoCycle = false
                    previewMode = mode
                }
            }

            Spacer(minLength: 0)
        }
        .task(id: previewAutoCycle) {
            await runAutoCycle()
        }
    }

    // MARK: - Session list preview

    @ViewBuilder
    private var sessionListPreviewSection: some View {
        sectionHeader(title: lang.t("settings.appearance.sessionPreview"), note: nil)

        SettingsPreviewStage(contentTopPadding: 20, contentBottomPadding: 28) {
            SessionListPanelPreview(
                sections: previewSessionSections,
                showsSections: editingPreferences.sessionGroup != .none,
                indicator: editingPreferences.sessionStateIndicator,
                profile: editingProfile,
                lang: lang
            )
            .padding(.horizontal, 18)
        }
        .padding(.top, 8)
    }

    private func runAutoCycle() async {
        guard previewAutoCycle else { return }

        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(Int(Self.autoCycleInterval * 1_000)))
            guard !Task.isCancelled, previewAutoCycle else { return }

            let order = Self.autoCycleOrder
            let current = order.firstIndex(of: previewMode) ?? 0
            let next = order[(current + 1) % order.count]
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.45)) {
                previewMode = next
            }
        }
    }

    // MARK: - 01 · Right slot

    @ViewBuilder
    private var rightSlotSection: some View {
        sectionHeader(
            title: lang.t("settings.appearance.rightSlot.title"),
            note: lang.t("settings.appearance.rightSlot.note")
        )

        HStack(spacing: 12) {
            rightSlotCard(.count,  icon: { CountBadgePreview(count: 3) },
                          title: lang.t("settings.appearance.rightSlot.count"))
            rightSlotCard(.agents, icon: { AgentsMiniGridPreview() },
                          title: lang.t("settings.appearance.rightSlot.agents"))
            rightSlotCard(.none,   icon: { Text("—")
                                      .font(.islandMono(size: 14, weight: .semibold))
                                      .foregroundStyle(V6Palette.paper.opacity(0.5)) },
                          title: lang.t("settings.appearance.rightSlot.none"))
        }
    }

    private func rightSlotCard<Content: View>(
        _ option: IslandRightSlot,
        @ViewBuilder icon: () -> Content,
        title: String
    ) -> some View {
        let selected = editingPreferences.rightSlot == option
        return Button {
            model.updateAppearancePreferences(for: editingProfile) { $0.rightSlot = option }
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    IslandThemes.current.shape(cornerRadius: 10)
                        .fill(V6Palette.paper.opacity(0.04))
                    icon()
                }
                .frame(height: 56)

                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(V6Palette.paper.opacity(0.85))
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                IslandThemes.current.shape(cornerRadius: 12)
                    .fill(V6Palette.paper.opacity(selected ? 0.07 : 0.02))
            )
            .overlay(
                IslandThemes.current.shape(cornerRadius: 12)
                    .stroke(
                        selected ? V6Palette.paper.opacity(0.9) : V6Palette.paper.opacity(0.08),
                        lineWidth: selected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 02 · Center label

    @ViewBuilder
    private var centerLabelSection: some View {
        sectionHeader(
            title: lang.t("settings.appearance.centerLabel.title"),
            note: lang.t("settings.appearance.centerLabel.note")
        )

        HStack(spacing: 12) {
            centerLabelCard(.agentAction, sample: "Claude · editing")
            centerLabelCard(.sessionName,  sample: "open-island")
            centerLabelCard(.off,          sample: "—")
        }
    }

    private func centerLabelCard(_ option: IslandCenterLabel, sample: String) -> some View {
        let selected = editingPreferences.centerLabel == option
        let title: String = switch option {
        case .agentAction: lang.t("settings.appearance.centerLabel.agentAction")
        case .sessionName: lang.t("settings.appearance.centerLabel.sessionName")
        case .off:         lang.t("settings.appearance.centerLabel.off")
        }
        return Button {
            model.updateAppearancePreferences(for: editingProfile) { $0.centerLabel = option }
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    IslandThemes.current.shape(cornerRadius: 10)
                        .fill(V6Palette.paper.opacity(0.04))
                    Text(sample)
                        .font(.islandMono(size: 11.5, weight: .medium))
                        .foregroundStyle(V6Palette.paper.opacity(option == .off ? 0.4 : 0.9))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 12)
                }
                .frame(height: 56)

                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(V6Palette.paper.opacity(0.85))
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                IslandThemes.current.shape(cornerRadius: 12)
                    .fill(V6Palette.paper.opacity(selected ? 0.07 : 0.02))
            )
            .overlay(
                IslandThemes.current.shape(cornerRadius: 12)
                    .stroke(
                        selected ? V6Palette.paper.opacity(0.9) : V6Palette.paper.opacity(0.08),
                        lineWidth: selected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 02 · Usage

    @ViewBuilder
    private var usageDisplaySection: some View {
        sectionHeader(
            title: lang.t("settings.appearance.usageDisplay.title"),
            note: lang.t("settings.appearance.usageDisplay.note")
        )

        HStack(spacing: 12) {
            ForEach(IslandUsageDisplay.allCases) { option in
                optionCard(
                    selected: editingPreferences.usageDisplay == option,
                    title: title(for: option)
                ) {
                    model.updateAppearancePreferences(for: editingProfile) { $0.usageDisplay = option }
                } icon: {
                    UsageDisplayPreview(option: option)
                }
            }
        }
    }

    // MARK: - 03 · Session state

    @ViewBuilder
    private var stateIndicatorSection: some View {
        sectionHeader(
            title: lang.t("settings.appearance.stateIndicator.title"),
            note: lang.t("settings.appearance.stateIndicator.note")
        )

        HStack(spacing: 12) {
            stateIndicatorCard(.animatedDot)
            stateIndicatorCard(.bar)
            stateIndicatorCard(.glyph)
            stateIndicatorCard(.tint)
        }
    }

    private func stateIndicatorCard(_ option: IslandSessionStateIndicator) -> some View {
        optionCard(
            selected: editingPreferences.sessionStateIndicator == option,
            title: title(for: option)
        ) {
            model.updateAppearancePreferences(for: editingProfile) { $0.sessionStateIndicator = option }
        } icon: {
            StateIndicatorPreview(option: option)
        }
    }

    // MARK: - 04 · Session grouping

    @ViewBuilder
    private var sessionGroupSection: some View {
        sectionHeader(
            title: lang.t("settings.appearance.sessionGroup.title"),
            note: lang.t("settings.appearance.sessionGroup.note")
        )

        HStack(spacing: 12) {
            ForEach(IslandSessionGroup.allCases) { option in
                optionCard(
                    selected: editingPreferences.sessionGroup == option,
                    title: title(for: option)
                ) {
                    model.updateAppearancePreferences(for: editingProfile) { $0.sessionGroup = option }
                } icon: {
                    SessionGroupPreview(option: option)
                }
            }
        }
    }

    // MARK: - 05 · Session sorting

    @ViewBuilder
    private var sessionSortSection: some View {
        sectionHeader(
            title: lang.t("settings.appearance.sessionSort.title"),
            note: lang.t("settings.appearance.sessionSort.note")
        )

        HStack(spacing: 12) {
            ForEach(IslandSessionSort.allCases) { option in
                optionCard(
                    selected: editingPreferences.sessionSort == option,
                    title: title(for: option)
                ) {
                    model.updateAppearancePreferences(for: editingProfile) { $0.sessionSort = option }
                } icon: {
                    SessionSortPreview(option: option)
                }
            }
        }
    }

    // MARK: - 06 · Done timeout

    @ViewBuilder
    private var staleThresholdSection: some View {
        sectionHeader(
            title: lang.t("settings.appearance.staleThreshold.title"),
            note: lang.t("settings.appearance.staleThreshold.note")
        )

        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 104), spacing: 12)],
            alignment: .leading,
            spacing: 12
        ) {
            ForEach(IslandCompletedStaleThreshold.allCases) { option in
                optionCard(
                    selected: editingPreferences.completedStaleThreshold == option,
                    title: title(for: option)
                ) {
                    model.updateAppearancePreferences(for: editingProfile) { $0.completedStaleThreshold = option }
                } icon: {
                    Text(title(for: option))
                        .font(.islandMono(size: 13, weight: .semibold))
                        .foregroundStyle(V6Palette.paper.opacity(0.9))
                }
            }
        }
    }

    // MARK: - Helpers

    private func partHeader(title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(V6Palette.paper.opacity(0.92))
    }

    private func optionCard<Icon: View>(
        selected: Bool,
        title: String,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    IslandThemes.current.shape(cornerRadius: 10)
                        .fill(V6Palette.paper.opacity(0.04))
                    icon()
                }
                .frame(height: 56)

                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(V6Palette.paper.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                IslandThemes.current.shape(cornerRadius: 12)
                    .fill(V6Palette.paper.opacity(selected ? 0.07 : 0.02))
            )
            .overlay(
                IslandThemes.current.shape(cornerRadius: 12)
                    .stroke(
                        selected ? V6Palette.paper.opacity(0.9) : V6Palette.paper.opacity(0.08),
                        lineWidth: selected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(title: String, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.islandMono(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(V6Palette.paper.opacity(0.55))
            if let note {
                Text(note)
                    .font(.system(size: 11.5))
                    .foregroundStyle(V6Palette.paper.opacity(0.38))
            }
        }
    }

    private func monoChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.islandMono(size: 10.5, weight: .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(selected ? V6Palette.ink : V6Palette.paper.opacity(0.7))
                .background(
                    Capsule().fill(
                        selected ? V6Palette.paper : V6Palette.paper.opacity(0.06)
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private func title(for mode: UnifiedBars.Mode) -> String {
        switch mode {
        case .idle:    lang.t("settings.appearance.state.idle")
        case .running: lang.t("settings.appearance.state.running")
        case .waiting: lang.t("settings.appearance.state.waiting")
        }
    }

    private func title(for option: IslandSessionStateIndicator) -> String {
        switch option {
        case .animatedDot: lang.t("settings.appearance.stateIndicator.animatedDot")
        case .bar:         lang.t("settings.appearance.stateIndicator.bar")
        case .glyph:       lang.t("settings.appearance.stateIndicator.glyph")
        case .tint:        lang.t("settings.appearance.stateIndicator.tint")
        }
    }

    private func title(for option: IslandUsageDisplay) -> String {
        switch option {
        case .hidden:  lang.t("settings.appearance.usageDisplay.hidden")
        case .compact: lang.t("settings.appearance.usageDisplay.compact")
        }
    }

    private func title(for option: IslandSessionGroup) -> String {
        switch option {
        case .none:    lang.t("settings.appearance.sessionGroup.none")
        case .state:   lang.t("settings.appearance.sessionGroup.state")
        case .agent:   lang.t("settings.appearance.sessionGroup.agent")
        case .project: lang.t("settings.appearance.sessionGroup.project")
        }
    }

    private func title(for option: IslandSessionSort) -> String {
        switch option {
        case .attention:  lang.t("settings.appearance.sessionSort.attention")
        case .lastUpdate: lang.t("settings.appearance.sessionSort.lastUpdate")
        }
    }

    private func title(for option: IslandCompletedStaleThreshold) -> String {
        switch option {
        case .twoMinutes:    lang.t("settings.appearance.staleThreshold.twoMinutes")
        case .fiveMinutes:   lang.t("settings.appearance.staleThreshold.fiveMinutes")
        case .tenMinutes:    lang.t("settings.appearance.staleThreshold.tenMinutes")
        case .twentyMinutes: lang.t("settings.appearance.staleThreshold.twentyMinutes")
        case .never:         lang.t("settings.appearance.staleThreshold.never")
        }
    }

    private var previewAgentCells: [AgentGridCell] {
        // Three Claude sessions, with one waiting when the preview mode is
        // `waiting` so the breathing tile is visible in the live preview.
        let claude = Color(hex: AgentTool.claudeCode.brandColorHex) ?? V6Palette.paper
        let waitingIdx = previewMode == .waiting ? 1 : -1
        return (0..<3).map { idx in
            if idx == waitingIdx {
                return .session(color: claude, state: .waiting)
            }
            return .session(color: claude, state: .running)
        }
    }

    private var previewLabel: String? {
        guard previewLayout == .external,
              editingPreferences.centerLabel != .off else { return nil }
        switch (previewMode, editingPreferences.centerLabel) {
        case (.idle, _):               return nil
        case (.waiting, _):            return lang.t("settings.appearance.preview.permissionNeeded")
        case (.running, .agentAction): return lang.t("settings.appearance.preview.agentEditing")
        case (.running, .sessionName): return "open-island"
        case (.running, .off):         return nil
        }
    }

    private var previewRightContent: IslandRightSlotContent? {
        switch editingPreferences.rightSlot {
        case .none: return nil
        case .count: return .count(3)
        case .agents:
            return .agents(previewAgentCells)
        }
    }

    private var previewSessionSections: [SessionPreviewSection] {
        SessionListPreviewFixture(
            group: editingPreferences.sessionGroup,
            sort: editingPreferences.sessionSort,
            doneAge: title(for: editingPreferences.completedStaleThreshold),
            lang: lang
        ).sections
    }
}
