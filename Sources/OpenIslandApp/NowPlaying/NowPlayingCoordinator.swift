import AppKit
import CoreGraphics
import Observation
import OpenIslandCore
import SwiftUI

/// Owns the one Now Playing feed the app runs: starts/stops the adapter
/// process, folds its NDJSON updates into `NowPlayingState`, derives the
/// artwork image (and a downsized thumbnail + glow tint from it), and turns
/// "play/pause/seek" into the one-shot adapter commands the opened surface's
/// transport controls call directly.
@MainActor
@Observable
final class NowPlayingCoordinator {
    private(set) var state: NowPlayingState?
    private(set) var artwork: NSImage?
    /// A small (28pt @2x) copy of `artwork`'s PNG data, for the closed-island
    /// accessory — never the full-resolution image, which can run to
    /// several hundred kilobytes and has no business sitting in a 14pt slot.
    private(set) var artworkThumbnail: Data?
    private(set) var tint: Color?
    /// Whether launching the adapter even looks possible — see
    /// `MediaRemoteAdapterProcess.isAvailable`'s doc comment for exactly
    /// what this does and doesn't check.
    private(set) var isAvailable: Bool

    @ObservationIgnored weak var overlay: OverlayUICoordinator?
    @ObservationIgnored var lang: LanguageManager = .shared
    @ObservationIgnored var settings: NowPlayingSettings = .init()

    @ObservationIgnored private let process: MediaRemoteAdapterProcess
    @ObservationIgnored private var lastArtworkData: Data?

    init(process: MediaRemoteAdapterProcess = MediaRemoteAdapterProcess()) {
        self.process = process
        self.isAvailable = process.isAvailable

        process.onUpdate = { [weak self] update in
            MainActor.assumeIsolated {
                self?.apply(update)
            }
        }
        process.onAvailabilityChange = { [weak self] available in
            MainActor.assumeIsolated {
                self?.isAvailable = available
            }
        }
    }

    func start() {
        process.start()
    }

    func stop() {
        process.stop()
    }

    // MARK: - Debug / harness

    /// Poses a fixed state with no process attached — how a harness scenario
    /// exercises the opened surface without a real adapter running
    /// underneath it. `nil` clears back to nothing playing.
    func loadDebugState(_ debugState: NowPlayingState?) {
        state = debugState
        updateArtwork(for: debugState, force: true)
    }

    // MARK: - Transport

    func togglePlayPause() { process.send(.togglePlayPause) }
    func play() { process.send(.play) }
    func pause() { process.send(.pause) }
    func nextTrack() { process.send(.nextTrack) }
    func previousTrack() { process.send(.previousTrack) }

    func seek(to seconds: TimeInterval) {
        process.seek(toMicroseconds: Int((seconds * 1_000_000).rounded()))
    }

    // MARK: - Applying updates

    private func apply(_ update: MediaRemoteAdapterProcess.Update) {
        let previousTitle = state?.title
        let next = NowPlayingReducer.apply(payload: update.payload, diff: update.diff, into: state)
        state = next
        updateArtwork(for: next, force: false)

        if let title = next?.title, next?.isPlaying == true, title != previousTitle {
            announceTrackChange(title: title, artist: next?.artist)
        }
    }

    private func updateArtwork(for state: NowPlayingState?, force: Bool) {
        guard let data = state?.artworkPNG else {
            artwork = nil
            artworkThumbnail = nil
            tint = nil
            lastArtworkData = nil
            return
        }
        guard force || data != lastArtworkData else { return }
        lastArtworkData = data

        guard let image = NSImage(data: data) else {
            artwork = nil
            artworkThumbnail = nil
            tint = nil
            return
        }
        artwork = image
        artworkThumbnail = Self.thumbnailPNG(from: image, pointSize: 28)
        tint = Self.tint(from: image)
    }

    private func announceTrackChange(title: String, artist: String?) {
        guard settings.sneakPeekOnTrackChange else { return }
        let text = artist.map { "\(title) — \($0)" } ?? title
        overlay?.presentSneakPeek(
            IslandSneakPeek(kind: .trackChanged, text: text, icon: "music.note", until: .now.addingTimeInterval(1.8))
        )
    }

    // MARK: - Artwork processing

    /// A small re-encoded PNG at `pointSize`@2x, for the closed-island
    /// accessory and the menu bar — never the source image's own resolution
    /// (typically 600–1200pt square album art).
    private static func thumbnailPNG(from image: NSImage, pointSize: CGFloat) -> Data? {
        let pixelSize = pointSize * 2
        let resized = NSImage(size: NSSize(width: pixelSize, height: pixelSize))
        resized.lockFocus()
        image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        resized.unlockFocus()

        guard let tiff = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    /// Down-samples to at most 32×32 raw pixels before handing off to
    /// `AlbumPalette.quantize` — a histogram over a million pixels of
    /// full-resolution art would cost far more than the glow it produces is
    /// worth.
    private static func tint(from image: NSImage) -> Color? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let side = 32
        var samples = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &samples,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        let (dominant, _) = AlbumPalette.quantize(rgbaSamples: samples, width: side, height: side)
        return Color(
            red: Double(dominant.red) / 255,
            green: Double(dominant.green) / 255,
            blue: Double(dominant.blue) / 255
        )
    }
}
