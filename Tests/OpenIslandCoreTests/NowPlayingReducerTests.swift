import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Now-playing reducer")
struct NowPlayingReducerTests {
    @Test("A non-diff payload replaces the state entirely")
    func fullReplace() {
        let payload: [String: JSONValue] = ["title": .string("First Song"), "artist": .string("A"), "playing": .bool(true)]
        let state = NowPlayingReducer.apply(payload: payload, diff: false, into: .init(title: "Old", artist: "Old"))

        #expect(state?.title == "First Song")
        #expect(state?.artist == "A")
        #expect(state?.isPlaying == true)
        // Not present in this payload — a full replace resets it, unlike a diff.
        #expect(state?.album == nil)
    }

    @Test("A non-diff payload with nothing in it means nothing is playing")
    func emptyFullReplaceMeansNil() {
        let state = NowPlayingReducer.apply(payload: [:], diff: false, into: .init(title: "Was Playing"))
        #expect(state == nil)
    }

    @Test("A diff payload only changes the keys it mentions")
    func diffMerge() {
        let current = NowPlayingState(title: "Song", artist: "Artist", album: "Album", isPlaying: true)
        let payload: [String: JSONValue] = ["isPlaying_unused_key": .bool(true), "elapsedTime": .number(12.0)]
        // `isPlaying_unused_key` isn't a real adapter key — only `elapsedTime`
        // should change anything here.
        let state = NowPlayingReducer.apply(payload: payload, diff: true, into: current)

        #expect(state?.title == "Song")
        #expect(state?.artist == "Artist")
        #expect(state?.album == "Album")
        #expect(state?.elapsed == 12.0)
    }

    @Test("An explicit JSON null clears that field")
    func diffNullClears() {
        let current = NowPlayingState(title: "Song", artist: "Artist", isPlaying: true)
        let payload: [String: JSONValue] = ["artist": .null]
        let state = NowPlayingReducer.apply(payload: payload, diff: true, into: current)

        #expect(state?.title == "Song")
        #expect(state?.artist == nil)
    }

    @Test("A key absent from a diff payload is left exactly as it was")
    func diffAbsentKeyUnchanged() {
        let current = NowPlayingState(title: "Song", artist: "Artist", duration: 200)
        let state = NowPlayingReducer.apply(payload: ["title": .string("Song")], diff: true, into: current)

        #expect(state?.artist == "Artist")
        #expect(state?.duration == 200)
    }

    @Test("An empty diff payload leaves the current state untouched")
    func emptyDiffIsNoOp() {
        let current = NowPlayingState(title: "Song")
        let state = NowPlayingReducer.apply(payload: [:], diff: true, into: current)
        #expect(state == current)
    }

    @Test("A diff with nothing playing yet starts from empty")
    func diffWithNoCurrentState() {
        let state = NowPlayingReducer.apply(
            payload: ["title": .string("Song"), "playing": .bool(true)],
            diff: true,
            into: nil
        )
        #expect(state?.title == "Song")
        #expect(state?.isPlaying == true)
        #expect(state?.playbackRate == 1.0)
    }

    @Test("parentApplicationBundleIdentifier wins over bundleIdentifier")
    func parentBundleIDWins() {
        let payload: [String: JSONValue] = [
            "bundleIdentifier": .string("com.apple.WebKit.WebContent"),
            "parentApplicationBundleIdentifier": .string("com.apple.Safari"),
        ]
        let state = NowPlayingReducer.apply(payload: payload, diff: false, into: nil)
        #expect(state?.bundleIdentifier == "com.apple.Safari")
    }

    @Test("bundleIdentifier alone is used when there's no parent")
    func bundleIDAloneIsUsed() {
        let state = NowPlayingReducer.apply(
            payload: ["bundleIdentifier": .string("com.spotify.client")],
            diff: false,
            into: nil
        )
        #expect(state?.bundleIdentifier == "com.spotify.client")
    }

    @Test("artworkData is decoded from base64 into artworkPNG")
    func artworkBase64Decode() {
        let bytes = Data([0x01, 0x02, 0x03, 0xFF])
        let payload: [String: JSONValue] = [
            "title": .string("Song"),
            "artworkData": .string(bytes.base64EncodedString()),
        ]
        let state = NowPlayingReducer.apply(payload: payload, diff: false, into: nil)
        #expect(state?.artworkPNG == bytes)
    }

    @Test("Malformed artworkData is ignored rather than crashing")
    func malformedArtworkIsIgnored() {
        let payload: [String: JSONValue] = ["title": .string("Song"), "artworkData": .string("not valid base64!!")]
        let state = NowPlayingReducer.apply(payload: payload, diff: false, into: nil)
        #expect(state?.title == "Song")
        #expect(state?.artworkPNG == nil)
    }
}
