import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Now-playing progress estimation")
struct NowPlayingProgressTests {
    private let epoch = Date(timeIntervalSince1970: 1_000_000)

    @Test("With no elapsed value at all, there's nothing to estimate")
    func noElapsedMeansNil() {
        let state = NowPlayingState(isPlaying: true, timestamp: epoch)
        #expect(NowPlayingProgress.elapsed(state, at: epoch.addingTimeInterval(5)) == nil)
    }

    @Test("A paused track does not advance, no matter how much time passes")
    func pausedDoesNotAdvance() {
        let state = NowPlayingState(isPlaying: false, elapsed: 30, timestamp: epoch)
        #expect(NowPlayingProgress.elapsed(state, at: epoch.addingTimeInterval(120)) == 30)
    }

    @Test("A playing track projects forward at the normal rate")
    func playingProjectsForward() {
        let state = NowPlayingState(isPlaying: true, elapsed: 30, timestamp: epoch, playbackRate: 1.0)
        let result = NowPlayingProgress.elapsed(state, at: epoch.addingTimeInterval(10))
        #expect(result == 40)
    }

    @Test("A 1.5x playback rate scales the projected delta")
    func playbackRateOneAndAHalf() {
        let state = NowPlayingState(isPlaying: true, elapsed: 30, timestamp: epoch, playbackRate: 1.5)
        let result = NowPlayingProgress.elapsed(state, at: epoch.addingTimeInterval(10))
        #expect(result == 45)
    }

    @Test("Projected elapsed is clamped to duration")
    func clampsToDuration() {
        let state = NowPlayingState(isPlaying: true, elapsed: 90, duration: 100, timestamp: epoch, playbackRate: 1.0)
        let result = NowPlayingProgress.elapsed(state, at: epoch.addingTimeInterval(60))
        #expect(result == 100)
    }

    @Test("Projected elapsed never goes negative, even with a backwards clock")
    func neverNegative() {
        let state = NowPlayingState(isPlaying: true, elapsed: 5, timestamp: epoch, playbackRate: 1.0)
        let result = NowPlayingProgress.elapsed(state, at: epoch.addingTimeInterval(-30))
        #expect(result == 0)
    }

    @Test("Playing with no timestamp falls back to the last reported value")
    func playingWithNoTimestampReturnsLastValue() {
        let state = NowPlayingState(isPlaying: true, elapsed: 42, timestamp: nil)
        #expect(NowPlayingProgress.elapsed(state, at: epoch) == 42)
    }
}
