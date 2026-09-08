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

    func makeNSView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        let player = AVQueuePlayer()
        player.isMuted = true
        let item = AVPlayerItem(url: url)
        context.coordinator.player = player
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: item)
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        player.play()
        return view
    }

    func updateNSView(_ nsView: PlayerLayerView, context: Context) {}

    /// Called when SwiftUI tears this view down — the board dismissing, or a
    /// setting change swapping it back to the gradient. Without this the
    /// looper would keep decoding frames nobody is looking at.
    static func dismantleNSView(_ nsView: PlayerLayerView, coordinator: Coordinator) {
        coordinator.player?.pause()
        coordinator.looper = nil
        coordinator.player = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
    }

    final class PlayerLayerView: NSView {
        let playerLayer = AVPlayerLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer = playerLayer
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}
