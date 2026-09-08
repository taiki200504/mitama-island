import SwiftUI
import OpenIslandCore

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Auto-height container: renders content directly (auto-sizing).
/// When content exceeds maxHeight, wraps in ScrollView at fixed maxHeight.
struct AutoHeightScrollView<Content: View>: View {
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

extension IslandPanelView {
    /// Routes on the island surface first — the three placeholder
    /// accessories get a bare title and stop there — and only the
    /// `sessionList` surface goes on to `openedRoute`, whose `.bootSplash`
    /// swaps itself out for `regularOpenedContent` after its own ring
    /// finishes while every other route renders the ordinary content
    /// directly.
    @ViewBuilder
    var openedContent: some View {
        switch model.islandSurface {
        case .sessionList:
            sessionListRoutedContent
        case .nowPlaying:
            placeholderOpenedContent(title: "NOW PLAYING")
        case .clipboard:
            placeholderOpenedContent(title: "CLIPBOARD")
        case .timer:
            placeholderOpenedContent(title: "TIMER")
        }
    }

    @ViewBuilder
    private var sessionListRoutedContent: some View {
        switch openedRoute {
        case .bootSplash:
            IslandBootSplashView { regularOpenedContent }
        case .notificationCard, .sessionList, .switcher:
            regularOpenedContent
        }
    }

    /// A bare title in the crystal-HUD display face — nothing else lives here
    /// yet. Each of these surfaces gets its real content in a later PR; this
    /// only keeps the surface reachable and visually inert in the meantime.
    private func placeholderOpenedContent(title: String) -> some View {
        VStack {
            Spacer()
            Text(title)
                .saoCaps(size: 16)
                .foregroundStyle(V6Palette.paper.opacity(0.4))
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    private var regularOpenedContent: some View {
        VStack(spacing: 8) {
            if !model.shelf.isEmpty {
                shelfBadge
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .transition(IslandTransition.resolved(IslandTransition.panelDrop))
            }

            if let notice = model.notice {
                noticeBar(notice)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .transition(IslandTransition.resolved(IslandTransition.panelDrop))
                    .id(notice.id)
            }

            if !model.hasAnyInstalledAgent {
                installHooksHint
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .transition(IslandTransition.resolved(IslandTransition.panelDrop))
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
        // The whole panel takes the drop, not a strip inside it. A target that
        // sits in the layout moves whenever a notice or a card arrives — and a
        // drop target that moves out from under a held file is not a target.
        .overlay { shelfDropInvitation }
        .dropDestination(for: URL.self) { urls, _ in
            model.putOnShelf(urls)
            return true
        } isTargeted: { isShelfTargeted = $0 }
    }

    /// What the camera and the microphone have to say for themselves.
    ///
    /// Sits above everything else because it is always about the thing that just
    /// happened — a refused permission, a gesture that did not read, words that
    /// made no sense. Tapping it takes it away early.
    private func noticeBar(_ notice: IslandNotice) -> some View {
        Button {
            model.clearNotice()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.islandText(size: 12, weight: .semibold))
                    .foregroundStyle(IslandThemes.current.accent)
                Text(notice.text)
                    .font(.islandText(size: 12, weight: .medium))
                    .foregroundStyle(V6Palette.paper.opacity(0.9))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                IslandThemes.current.shape(cornerRadius: 10)
                    .fill(V6Palette.paper.opacity(0.07))
                    .overlay(
                        IslandThemes.current.shape(cornerRadius: 10)
                            .stroke(IslandThemes.current.accent.opacity(0.30), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(notice.text)
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
                    .foregroundStyle(V6Palette.paper.opacity(0.85))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.islandText(size: 10, weight: .semibold))
                    .foregroundStyle(V6Palette.paper.opacity(0.4))
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
                .tint(V6Palette.paper.opacity(0.7))
                .scaleEffect(0.8)
            Text(model.lang.t("island.checkingTerminals"))
                .font(.islandText(size: 14, weight: .medium))
                .foregroundStyle(V6Palette.paper.opacity(0.58))
            Text(model.lang.t("island.terminalOwnership"))
                .font(.islandText(size: 12))
                .foregroundStyle(V6Palette.paper.opacity(0.28))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(model.lang.t("island.noTerminals"))
                .font(.islandText(size: 14, weight: .medium))
                .foregroundStyle(V6Palette.paper.opacity(0.4))
            Text(model.recentSessions.isEmpty
                ? model.lang.t("island.startAgent")
                : model.lang.t("island.recentSessions"))
                .font(.islandText(size: 12))
                .foregroundStyle(V6Palette.paper.opacity(0.25))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

}
