import AVFoundation
import SwiftUI

/// Loops a single video file behind the idle board.
///
/// Muted and looping so it behaves like the gradient it stands in for: no
/// sound, no ending, nothing to interact with. `AVPlayerLooper` rather than
/// hand-rolled `didPlayToEndTime` observing — it exists specifically so a
/// gapless loop doesn't have to be reinvented per feature.
struct AmbientVideoLayerView: NSViewRepresentable {
    let url: URL
    /// Overridable so a test can hand in a player it already holds a
    /// reference to, rather than reaching into what `makeNSView` built.
    /// Production never sets this — a fresh `AVQueuePlayer` every load.
    var makePlayer: () -> AVQueuePlayer = { AVQueuePlayer() }

    func makeNSView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        context.coordinator.load(url: url, into: view, makePlayer: makePlayer)
        return view
    }

    /// A setting change swaps `url` to a different clip without tearing the
    /// view down — SwiftUI reuses it. Rebuilding only when the URL actually
    /// moved keeps every other update pass a no-op rather than restarting
    /// playback on every clock tick the board redraws for.
    func updateNSView(_ nsView: PlayerLayerView, context: Context) {
        guard context.coordinator.currentURL != url else { return }
        context.coordinator.load(url: url, into: nsView, makePlayer: makePlayer)
    }

    /// Called when SwiftUI tears this view down — the board dismissing, or a
    /// setting change swapping it back to the gradient. Without this the
    /// looper would keep decoding frames nobody is looking at.
    static func dismantleNSView(_ nsView: PlayerLayerView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        private(set) var currentURL: URL?
        private(set) var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?

        /// Tears down whatever was playing and starts the new clip. Also the
        /// entry point `makeNSView` uses for the first load — there's nothing
        /// to tear down the first time, but the same one path is simpler than
        /// two.
        func load(url: URL, into view: PlayerLayerView, makePlayer: () -> AVQueuePlayer) {
            tearDown()

            let player = makePlayer()
            player.isMuted = true
            let item = AVPlayerItem(url: url)
            looper = AVPlayerLooper(player: player, templateItem: item)
            view.playerLayer.player = player
            view.playerLayer.videoGravity = .resizeAspectFill

            // The view tells the *current* player to pause or resume as its
            // own on-screen state changes — a stale closure from a clip that
            // was already swapped out never runs, because `load` always
            // overwrites this before the old player is released.
            view.onVisibilityChange = { [weak player] isVisible in
                if isVisible { player?.play() } else { player?.pause() }
            }

            self.player = player
            currentURL = url
            player.play()
        }

        /// Pauses playback and drops the player and looper. Safe to call when
        /// nothing is loaded — `load` calls this unconditionally before
        /// starting the next clip.
        func tearDown() {
            player?.pause()
            looper = nil
            player = nil
            currentURL = nil
        }
    }

    final class PlayerLayerView: NSView {
        let playerLayer = AVPlayerLayer()
        /// Told whenever this view's on-screen state changes, so playback
        /// pauses the moment nobody can see it rather than only when SwiftUI
        /// eventually tears the whole view down.
        var onVisibilityChange: ((Bool) -> Void)?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer = playerLayer
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onVisibilityChange?(window != nil && !isHiddenOrHasHiddenAncestor)
        }

        override func viewDidHide() {
            super.viewDidHide()
            onVisibilityChange?(false)
        }

        override func viewDidUnhide() {
            super.viewDidUnhide()
            onVisibilityChange?(window != nil)
        }
    }
}
