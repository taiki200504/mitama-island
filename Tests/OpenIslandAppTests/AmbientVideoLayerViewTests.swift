import AVFoundation
import Testing
@testable import OpenIslandApp

/// No wall-clock waits: these check the coordinator's bookkeeping and the
/// `AVQueuePlayer.rate` it drives, never actual decoded video — a real file
/// isn't needed for either.
@MainActor
@Suite struct AmbientVideoLayerViewTests {
    private func url(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/\(name)") }

    @Test("A new URL tears down the old player rather than reusing its item")
    func urlChangeRebuildsThePlayer() {
        let coordinator = AmbientVideoLayerView.Coordinator()
        let view = AmbientVideoLayerView.PlayerLayerView()

        let first = AVQueuePlayer()
        coordinator.load(url: url("a.mov"), into: view, makePlayer: { first })
        #expect(coordinator.currentURL == url("a.mov"))
        #expect(coordinator.player === first)

        let second = AVQueuePlayer()
        coordinator.load(url: url("b.mov"), into: view, makePlayer: { second })
        #expect(coordinator.currentURL == url("b.mov"))
        #expect(coordinator.player === second)
        #expect(first.rate == 0, "the superseded player should have been paused, not left running")
    }

    @Test("Hiding the view pauses playback without dropping the player")
    func hidingPausesPlayback() {
        let coordinator = AmbientVideoLayerView.Coordinator()
        let view = AmbientVideoLayerView.PlayerLayerView()
        let player = AVQueuePlayer()
        coordinator.load(url: url("a.mov"), into: view, makePlayer: { player })
        #expect(player.rate != 0)

        view.onVisibilityChange?(false)
        #expect(player.rate == 0)
        #expect(coordinator.player === player, "hiding pauses in place — it doesn't tear the player down")

        view.onVisibilityChange?(true)
        #expect(player.rate != 0)
    }
}
