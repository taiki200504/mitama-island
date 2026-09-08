import AppKit
import SwiftUI
import OpenIslandCore

/// The opened `.nowPlaying` surface: artwork, title/artist/album, a
/// draggable seek bar, transport controls and the source app. Only this view
/// refreshes on a 1-second clock — the closed-island accessory and the menu
/// bar both read `NowPlayingCoordinator.state` on demand instead of ticking.
struct NowPlayingSurfaceView: View {
    var model: AppModel

    private var coordinator: NowPlayingCoordinator { model.nowPlaying }
    private var lang: LanguageManager { model.lang }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(now: context.date)
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if let state = coordinator.state, state.title != nil {
            playingContent(state: state, now: now)
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "music.note")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(V6Palette.paper.opacity(0.28))
            Text(lang.t("nowPlaying.empty"))
                .saoCaps(size: 12)
                .foregroundStyle(V6Palette.paper.opacity(0.4))
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    private func playingContent(state: NowPlayingState, now: Date) -> some View {
        VStack(spacing: 14) {
            artworkView

            VStack(spacing: 3) {
                Text(state.title ?? "")
                    .font(.islandText(size: 14, weight: .semibold))
                    .foregroundStyle(V6Palette.paper.opacity(0.92))
                    .lineLimit(1)
                if let artist = state.artist {
                    Text(artist)
                        .font(.islandText(size: 11.5))
                        .foregroundStyle(V6Palette.paper.opacity(0.6))
                        .lineLimit(1)
                }
                if let album = state.album {
                    Text(album)
                        .font(.islandText(size: 10.5))
                        .foregroundStyle(V6Palette.paper.opacity(0.4))
                        .lineLimit(1)
                }
            }

            seekSection(state: state, now: now)
            transportRow(state: state)
            sourceRow(state: state)
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Artwork

    private var artworkView: some View {
        Group {
            if let artwork = coordinator.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(V6Palette.paper.opacity(0.08))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundStyle(V6Palette.paper.opacity(0.3))
                    )
            }
        }
    }

    // MARK: - Seek

    private func seekSection(state: NowPlayingState, now: Date) -> some View {
        let elapsed = NowPlayingProgress.elapsed(state, at: now) ?? 0
        let duration = max(0, state.duration ?? 0)
        let fraction = duration > 0 ? min(max(elapsed / duration, 0), 1) : 0

        return VStack(spacing: 4) {
            NowPlayingSeekBar(progress: fraction) { seekFraction in
                guard duration > 0 else { return }
                coordinator.seek(to: seekFraction * duration)
            }

            HStack {
                Text(Self.timeString(elapsed))
                    .font(.islandMono(size: 10, weight: .medium))
                    .foregroundStyle(V6Palette.paper.opacity(0.45))
                Spacer()
                Text(Self.timeString(duration))
                    .font(.islandMono(size: 10, weight: .medium))
                    .foregroundStyle(V6Palette.paper.opacity(0.45))
            }
        }
    }

    // MARK: - Transport

    private func transportRow(state: NowPlayingState) -> some View {
        HStack(spacing: 10) {
            Button(action: { coordinator.previousTrack() }) {
                Image(systemName: "backward.fill")
            }
            .buttonStyle(IslandActionButtonStyle(kind: .secondary, surface: .darkShell))

            Button(action: { coordinator.togglePlayPause() }) {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(IslandActionButtonStyle(kind: .primary, expands: true, surface: .darkShell))

            Button(action: { coordinator.nextTrack() }) {
                Image(systemName: "forward.fill")
            }
            .buttonStyle(IslandActionButtonStyle(kind: .secondary, surface: .darkShell))
        }
    }

    // MARK: - Source app

    @ViewBuilder
    private func sourceRow(state: NowPlayingState) -> some View {
        if let bundleID = state.bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            HStack(spacing: 6) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 14, height: 14)
                Text(FileManager.default.displayName(atPath: url.path))
                    .font(.islandText(size: 10.5))
                    .foregroundStyle(V6Palette.paper.opacity(0.4))
            }
        }
    }

    private static func timeString(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// A draggable `SAOGaugeShape` progress bar. Dragging previews the seek
/// position locally; the coordinator only actually seeks once the drag ends,
/// so a slow drag doesn't spam the adapter with one `seek` call per pixel.
private struct NowPlayingSeekBar: View {
    let progress: Double
    let onSeek: (Double) -> Void

    @State private var dragFraction: Double?

    private var displayedFraction: Double { dragFraction ?? progress }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                SAOGaugeShape(fraction: 1, isTrack: true)
                    .fill(V6Palette.paper.opacity(0.14))
                SAOGaugeShape(fraction: displayedFraction)
                    .fill(SAOGrammar.Palette.accentOrange)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragFraction = Self.fraction(for: value.location.x, in: geometry.size.width)
                    }
                    .onEnded { value in
                        let fraction = Self.fraction(for: value.location.x, in: geometry.size.width)
                        dragFraction = nil
                        onSeek(fraction)
                    }
            )
        }
        .frame(height: 6)
    }

    private static func fraction(for x: CGFloat, in width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(max(0, x / width), 1))
    }
}
