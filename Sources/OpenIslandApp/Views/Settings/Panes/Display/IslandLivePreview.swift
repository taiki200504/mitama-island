import OpenIslandCore
import SwiftUI

/// The display pane's island preview: the real closed pill, or the opened
/// session list at a reduced scale, switched by a chip that comes forward
/// while the pointer is over the stage.
///
/// Both states draw the views the island itself draws — `V6ClosedPill` and
/// `SessionListPanelPreview` over the opened shell — so a preference changed
/// below shows up here exactly as it will on the notch.
struct IslandLivePreview: View {
    let mode: UnifiedBars.Mode
    let label: String?
    let rightSlot: IslandRightSlotContent?
    let layout: V6ClosedLayout
    let sections: [SessionPreviewSection]
    let showsSections: Bool
    let indicator: IslandSessionStateIndicator
    let profile: IslandAppearanceDisplayProfile
    let lang: LanguageManager

    /// How large the opened surface is drawn relative to the real island.
    /// Small enough to leave the controls beneath it in view, large enough
    /// that a row's text is still readable.
    static let openedScale: CGFloat = 0.72

    private static let physicalNotchWidth: CGFloat = 180
    private static let pillHeight: CGFloat = 32

    @State private var showsOpened = false
    @State private var isHovering = false
    /// The opened panel's unscaled height. `scaleEffect` shrinks the drawing
    /// but not the space it takes, so the stage reserves this times the scale.
    @State private var openedHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if showsOpened {
                    openedSurface
                } else {
                    closedSurface
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .transition(.opacity)

            surfaceChip
        }
        .animation(IslandMotion.resolved(IslandMotion.hover), value: showsOpened)
        .onHover { hovering in
            withAnimation(IslandMotion.resolved(IslandMotion.hover)) {
                isHovering = hovering
            }
        }
    }

    // MARK: - Closed

    private var closedSurface: some View {
        ZStack(alignment: .top) {
            if layout == .macbook {
                // The hardware cutout the pill wraps, pinned to the top the
                // way the real one sits at the top of the display.
                V6ClosedPillShape()
                    .fill(Color.black)
                    .frame(width: Self.physicalNotchWidth, height: Self.pillHeight)
            }

            V6ClosedPill(
                mode: mode,
                label: label,
                rightSlot: rightSlot,
                layout: layout,
                physicalNotchWidth: Self.physicalNotchWidth
            )
        }
        .frame(height: Self.pillHeight)
    }

    // MARK: - Opened

    private var openedSurface: some View {
        SessionListPanelPreview(
            sections: sections,
            showsSections: showsSections,
            indicator: indicator,
            profile: profile,
            lang: lang
        )
        .background(
            GeometryReader { geometry in
                Color.clear.preference(key: OpenedPreviewHeightKey.self, value: geometry.size.height)
            }
        )
        .onPreferenceChange(OpenedPreviewHeightKey.self) { openedHeight = $0 }
        .scaleEffect(Self.openedScale, anchor: .top)
        .frame(height: openedHeight * Self.openedScale, alignment: .top)
        // The panel is laid out at full width and only drawn smaller, so the
        // space it no longer covers must not take clicks meant for the chip.
        .allowsHitTesting(false)
    }

    // MARK: - Chip

    /// Always present so keyboard and VoiceOver users can reach it; hover
    /// only brings it forward, it never decides whether it exists.
    private var surfaceChip: some View {
        HStack(spacing: 2) {
            chipSegment(title: lang.t("settings.appearance.preview.closed"), selected: !showsOpened) {
                showsOpened = false
            }
            chipSegment(title: lang.t("settings.appearance.preview.opened"), selected: showsOpened) {
                showsOpened = true
            }
        }
        .padding(2)
        .background(Capsule().fill(V6Palette.ink.opacity(0.72)))
        .overlay(Capsule().strokeBorder(SAOGrammar.Palette.hairline, lineWidth: 1))
        .opacity(isHovering ? 1 : 0.55)
        .padding(.trailing, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(lang.t("settings.appearance.preview.surface"))
    }

    private func chipSegment(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.islandMono(size: 10, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .foregroundStyle(selected ? V6Palette.ink : V6Palette.paper.opacity(0.75))
                .background(Capsule().fill(selected ? IslandThemes.current.accent : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct OpenedPreviewHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
