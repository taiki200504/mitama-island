import AppKit
import SwiftUI
import OpenIslandCore

/// The opened `.clipboard` surface: a search field over the recent-copies
/// list, each row copying (or pasting) itself back on a tap.
struct ClipboardSurfaceView: View {
    var model: AppModel

    @State private var query = ""

    private var lang: LanguageManager { model.lang }

    private var filteredItems: [ClipboardItem] {
        ClipboardSearch.filter(model.clipboard.items, query: query)
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(lang.t("clipboard.title"))
                .saoCaps(size: 13, text: lang.t("clipboard.title"))
                .foregroundStyle(V6Palette.paper.opacity(0.55))
                .padding(.top, 4)

            if !model.clipboard.items.isEmpty {
                searchField
            }

            if filteredItems.isEmpty {
                emptyState
            } else {
                AutoHeightScrollView(maxHeight: 260) {
                    VStack(spacing: 6) {
                        ForEach(filteredItems) { item in
                            row(for: item)
                        }
                    }
                }
            }

            if !model.clipboard.items.isEmpty {
                Button(lang.t("clipboard.clearAll")) {
                    model.clipboard.clear()
                }
                .buttonStyle(.plain)
                .font(.islandText(size: 10.5))
                .foregroundStyle(V6Palette.paper.opacity(0.4))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.islandText(size: 11))
                .foregroundStyle(V6Palette.paper.opacity(0.4))
            ReplyTextField(
                placeholder: lang.t("clipboard.search.placeholder"),
                text: $query,
                onSubmit: {}
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(V6Palette.paper.opacity(0.06), in: Capsule())
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text(model.clipboard.items.isEmpty ? lang.t("clipboard.empty") : lang.t("clipboard.search.noMatches"))
                .font(.islandText(size: 12))
                .foregroundStyle(V6Palette.paper.opacity(0.4))
        }
        .frame(maxWidth: .infinity, minHeight: 90)
    }

    // MARK: - Rows

    private func row(for item: ClipboardItem) -> some View {
        Button {
            // Held down at the moment of the click, not sampled later — the
            // same technique `ShelfItemDragSource.onOptionClick` uses for its
            // own modified click, since SwiftUI has no built-in modified tap
            // gesture.
            if NSEvent.modifierFlags.contains(.option) {
                model.clipboard.remove(item)
            } else {
                model.selectClipboardItem(item)
            }
        } label: {
            HStack(spacing: 10) {
                kindIcon(for: item)

                VStack(alignment: .leading, spacing: 2) {
                    Text(preview(for: item))
                        .font(.islandText(size: 12))
                        .foregroundStyle(V6Palette.paper.opacity(0.88))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .truncationMode(.tail)

                    HStack(spacing: 5) {
                        if let sourceIcon = sourceAppIcon(for: item) {
                            Image(nsImage: sourceIcon)
                                .resizable()
                                .frame(width: 11, height: 11)
                        }
                        Text(relativeTime(for: item.copiedAt))
                            .font(.islandText(size: 10))
                            .foregroundStyle(V6Palette.paper.opacity(0.4))
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(V6Palette.paper.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func kindIcon(for item: ClipboardItem) -> some View {
        Group {
            switch item.kind {
            case .text:
                Image(systemName: "text.alignleft")
            case let .image(pngData, thumbnail):
                if let nsImage = NSImage(data: thumbnail ?? pngData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo")
                }
            case .fileURLs:
                Image(systemName: "doc.on.doc")
            }
        }
        .font(.islandText(size: 13))
        .foregroundStyle(V6Palette.paper.opacity(0.6))
        .frame(width: 26, height: 26)
        .background(V6Palette.paper.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func preview(for item: ClipboardItem) -> String {
        switch item.kind {
        case let .text(string):
            string
        case .image:
            lang.t("clipboard.kind.image")
        case let .fileURLs(urls):
            urls.map(\.lastPathComponent).joined(separator: ", ")
        }
    }

    private func sourceAppIcon(for item: ClipboardItem) -> NSImage? {
        guard let bundleID = item.sourceBundleID,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }

    private func relativeTime(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}
