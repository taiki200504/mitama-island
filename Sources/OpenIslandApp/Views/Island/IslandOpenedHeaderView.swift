import SwiftUI
import OpenIslandCore

extension IslandPanelView {
    @ViewBuilder
    var openedHeaderContent: some View {
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
            if cameraIsWatching {
                cameraWatchingMark
            }

            headerIconButton(
                systemName: model.isSoundMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                tint: model.isSoundMuted
                    ? IslandThemes.current.statusTints.waitingForApproval.opacity(0.92)
                    : V6Palette.paper.opacity(0.62)
            ) {
                model.toggleSoundMuted()
            }

            headerIconButton(systemName: "gearshape.fill", tint: V6Palette.paper.opacity(0.62)) {
                model.showSettings()
            }

            headerIconButton(
                systemName: "power",
                tint: V6Palette.paper.opacity(0.62),
                accessibilityLabel: model.lang.t("island.quit.confirmTitle")
            ) {
                showingQuitConfirmation = true
            }
        }
    }

    /// Says the camera is open, for as long as it is open.
    ///
    /// The status notice used to be the only sign of this, and a notice expires
    /// on its own timer: a card that had been sitting for a minute looked
    /// exactly like one the camera had never opened for. Measured 2026-08-29 —
    /// the camera opened four times and was invisible after the first seconds
    /// of each, which is why the feature read as broken.
    ///
    /// Not a button. There is nothing to press: the camera is open because a
    /// card is waiting, and it closes when the card is answered.
    private var cameraWatchingMark: some View {
        let tint = IslandThemes.current.statusTints.waitingForAnswer
        return Image(systemName: "hand.raised.fill")
            .font(.islandText(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: Self.headerControlButtonSize, height: Self.headerControlButtonSize)
            .background(tint.opacity(0.16), in: Circle())
            .shadow(color: tint.opacity(0.6), radius: IslandThemes.current.glowRadius)
            .accessibilityLabel(model.lang.t("camera.watching"))
            .help(model.lang.t("camera.watching"))
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
                .background(V6Palette.paper.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? systemName)
    }

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
                .foregroundStyle(V6Palette.paper.opacity(0.74))

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
        .background(V6Palette.paper.opacity(0.055), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(V6Palette.paper.opacity(0.06), lineWidth: 1)
        )
        .help(usageHelpText(for: provider))
    }

    private func usageWindowFigures(_ window: UsageWindowPresentation) -> some View {
        HStack(spacing: 4) {
            Text(window.label)
                .font(.islandMono(size: 10.5, weight: .semibold))
                .foregroundStyle(V6Palette.paper.opacity(0.42))

            Text(usageValueText(for: window.usedPercentage))
                .font(.islandMono(size: 11.5, weight: .bold))
                .foregroundStyle(usageColor(for: window.usedPercentage))

            if let resetsAt = window.resetsAt,
               let remaining = remainingDurationString(until: resetsAt) {
                Text(remaining)
                    .font(.islandMono(size: 10.5, weight: .medium))
                    .foregroundStyle(V6Palette.paper.opacity(0.38))
            }
        }
    }

    private func peakUsageFigures(_ provider: UsageProviderPresentation) -> some View {
        HStack(spacing: 5) {
            Text(provider.peakWindowLabel)
                .font(.islandMono(size: 10.5, weight: .semibold))
                .foregroundStyle(V6Palette.paper.opacity(0.42))

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
                    .foregroundStyle(V6Palette.paper.opacity(0.38))
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
            .background(V6Palette.paper.opacity(0.08), in: Capsule())
    }

    /// Nearly out / getting close / plenty left, in the theme's own three
    /// colours. The status tints already carry "this is bad", "this wants your
    /// attention" and "this is fine" for sessions, so a usage meter that
    /// invents its own red-amber-green would read as a second vocabulary.
    private func usageColor(for percentage: Double) -> Color {
        let tints = IslandThemes.current.statusTints
        switch percentage {
        case 90...:
            return tints.critical.opacity(0.95)
        case 70..<90:
            return tints.waitingForApproval.opacity(0.95)
        default:
            return tints.completed.opacity(0.95)
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
