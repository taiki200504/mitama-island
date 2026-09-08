import SwiftUI
import OpenIslandCore

extension IslandPanelView {
    /// What is on the shelf, in one line. It opens up when the pointer rests on
    /// it: the sessions are what the island is for, and a row of file icons
    /// pushing them down all day is the wrong trade.
    @ViewBuilder
    var shelfBadge: some View {
        let theme = IslandThemes.current

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "tray.full")
                    .font(.islandText(size: 11))
                    .foregroundStyle(theme.accent)
                Text(model.lang.t("shelf.title"))
                    .font(.islandText(size: 11, weight: .medium))
                    .foregroundStyle(V6Palette.paper.opacity(0.75))
                Text("\(model.shelf.items.count)")
                    .font(.islandText(size: 10))
                    .foregroundStyle(V6Palette.paper.opacity(0.45))
                Spacer(minLength: 0)
                if isShelfExpanded {
                    Button(model.lang.t("shelf.clear")) { model.shelf.removeAll() }
                        .buttonStyle(.plain)
                        .font(.islandText(size: 10))
                        .foregroundStyle(V6Palette.paper.opacity(0.4))
                }
            }

            if isShelfExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.shelf.items) { item in
                            shelfChip(item, theme: theme)
                        }
                    }
                }
                .frame(height: 46)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(shelfBackground(theme: theme))
        .onHover { isShelfBadgeHovered = $0 }
        .animation(theme.animationProfile.pop, value: isShelfExpanded)
    }

    /// Hovered by the pointer, or forced open by a debug/harness scenario that
    /// needs the chips on screen for a screenshot without a real pointer.
    private var isShelfExpanded: Bool {
        isShelfBadgeHovered || model.debugShelfBadgeForcedExpanded
    }

    /// Only ever on screen while something is being carried over the island.
    @ViewBuilder
    var shelfDropInvitation: some View {
        // Real-time file counts and sizes are not available while merely
        // hovering — `isShelfTargeted` is the only signal SwiftUI gives before
        // the drop lands — so this is `.idle`/`.invited` only. A refusal is
        // only known once `putOnShelf` actually tries, and shows up as the
        // closed-pill message instead.
        let feedback = ShelfDropFeedback.state(hoveringCount: isShelfTargeted ? 1 : 0)
        if case .invited = feedback {
            let theme = IslandThemes.current

            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.islandText(size: 20))
                Text(model.lang.t("shelf.empty"))
                    .font(.islandText(size: 12))
            }
            .foregroundStyle(V6Palette.paper.opacity(0.85))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(V6Palette.ink.opacity(0.82))
            .overlay(
                theme.shape(cornerRadius: 12)
                    .strokeBorder(theme.accent.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .padding(6)
            )
            .transition(.opacity)
        }
    }

    private func shelfBackground(theme: SAOTheme) -> some View {
        theme.shape(cornerRadius: 10)
            .fill(V6Palette.paper.opacity(isShelfTargeted ? 0.10 : 0.04))
            .overlay(
                theme.shape(cornerRadius: 10)
                    .strokeBorder(
                        theme.accent.opacity(isShelfTargeted ? 0.55 : 0.14),
                        style: StrokeStyle(lineWidth: 1, dash: model.shelf.isEmpty ? [4, 3] : [])
                    )
            )
    }

    /// One item. Dragging it hands over the copy's own URL, so it lands in
    /// Finder as a real file rather than as text.
    private func shelfChip(_ item: ShelfItem, theme: SAOTheme) -> some View {
        let url = model.shelf.fileURL(for: item)

        return VStack(spacing: 2) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 22, height: 22)
            Text(item.displayName)
                .font(.islandText(size: 9))
                .foregroundStyle(V6Palette.paper.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.middle)
            if let caption = model.shelfExpiryCaption(for: item) {
                Text(caption)
                    .font(.islandText(size: 8))
                    .foregroundStyle(V6Palette.paper.opacity(0.4))
                    .lineLimit(1)
            }
        }
        .frame(width: 62)
        .padding(.vertical, 2)
        .background(theme.shape(cornerRadius: 8).fill(V6Palette.paper.opacity(0.05)))
        .overlay {
            // Dragging a chip out is a move, not a copy: what leaves the shelf
            // has left it. AppKit is the only place that says so.
            ShelfItemDragSource(
                url: url,
                onTakenAway: { model.shelf.remove(item) },
                onOptionClick: { model.shelf.remove(item) },
                menuEntries: [
                    .init(
                        title: model.lang.t("shelf.airDrop"),
                        action: { _ in model.shelf.airDrop(item) }
                    ),
                    .init(
                        title: model.lang.t("shelf.share"),
                        action: { view in model.shelf.share(item, from: view) }
                    ),
                    .init(
                        title: model.lang.t("shelf.revealInFinder"),
                        action: { _ in NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    ),
                    .init(
                        title: model.lang.t("shelf.remove"),
                        action: { _ in model.shelf.remove(item) }
                    ),
                ]
            )
        }
        .help(item.displayName)
    }

}
