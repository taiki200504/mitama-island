import Foundation

/// What is playing right now, as far as the island knows. Built by merging
/// `MediaRemoteAdapterProcess`'s NDJSON updates through `NowPlayingReducer`
/// — nothing here talks to a process or a framework, so it can be tested
/// with plain dictionaries.
public struct NowPlayingState: Codable, Sendable, Equatable {
    public var title: String?
    public var artist: String?
    public var album: String?
    public var isPlaying: Bool
    /// Seconds into the track *as of* `timestamp` — not "right now". Use
    /// `NowPlayingProgress.elapsed(_:at:)` for a live estimate.
    public var elapsed: TimeInterval?
    public var duration: TimeInterval?
    public var timestamp: Date?
    public var playbackRate: Double
    /// Decoded from the adapter's base64 `artworkData`. Whatever image
    /// format the source app handed MediaRemote — not necessarily PNG —
    /// `NSImage` doesn't care.
    public var artworkPNG: Data?
    /// The resolved bundle identifier: `parentApplicationBundleIdentifier`
    /// when the adapter reports one (a browser tab playing through a system
    /// extension, for instance), `bundleIdentifier` otherwise.
    public var bundleIdentifier: String?

    public init(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        isPlaying: Bool = false,
        elapsed: TimeInterval? = nil,
        duration: TimeInterval? = nil,
        timestamp: Date? = nil,
        playbackRate: Double = 1.0,
        artworkPNG: Data? = nil,
        bundleIdentifier: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = isPlaying
        self.elapsed = elapsed
        self.duration = duration
        self.timestamp = timestamp
        self.playbackRate = playbackRate
        self.artworkPNG = artworkPNG
        self.bundleIdentifier = bundleIdentifier
    }

    /// Nothing playing, nothing known — `NowPlayingReducer` starts a `diff`
    /// stream from here.
    public static let empty = NowPlayingState()
}

/// Turns one line of `mediaremote-adapter.pl stream` output into the next
/// `NowPlayingState` — or `nil` once nothing is playing.
///
/// `payload` is the decoded JSON object for that line, as `JSONValue` rather
/// than `JSONSerialization`'s own `[String: Any]` — `Any` isn't `Sendable`,
/// and this crosses onto `NowPlayingCoordinator`'s `@MainActor`. `.null`
/// still reads as "this key is present with a null value" rather than being
/// silently dropped. The adapter's own `diff` flag decides how it's applied:
///
/// - `diff == false`: `payload` is the complete current state. A key that's
///   missing means "no value", exactly like starting from `.empty`.
/// - `diff == true`: only the keys present in `payload` change. A key set to
///   JSON `null` clears that field; a key absent from `payload` altogether
///   is left exactly as `current` had it.
public enum NowPlayingReducer {
    public static func apply(
        payload: [String: JSONValue],
        diff: Bool,
        into current: NowPlayingState?
    ) -> NowPlayingState? {
        if !diff {
            // A non-diff payload with nothing in it is the adapter's way of
            // saying no media player is reporting anything at all.
            guard !payload.isEmpty else { return nil }
            return NowPlayingState.empty.merging(payload)
        }

        guard !payload.isEmpty else { return current }
        return (current ?? .empty).merging(payload)
    }
}

extension NowPlayingState {
    /// How one raw JSON field was found in a diff payload: not mentioned at
    /// all (leave the field alone), explicitly `null` (clear it back to its
    /// default), or carrying a real value.
    private enum FieldUpdate<T> {
        case absent
        case cleared
        case value(T)
    }

    private static func field<T>(
        _ raw: [String: JSONValue],
        _ key: String,
        extract: (JSONValue) -> T?
    ) -> FieldUpdate<T> {
        guard let value = raw[key] else { return .absent }
        if value.isNull { return .cleared }
        // A field of the wrong type is malformed input from the adapter —
        // safer to leave the existing value alone than to guess.
        guard let typed = extract(value) else { return .absent }
        return .value(typed)
    }

    fileprivate func merging(_ raw: [String: JSONValue]) -> NowPlayingState {
        var result = self

        switch Self.field(raw, "title", extract: { $0.stringValue }) {
        case .absent: break
        case .cleared: result.title = nil
        case .value(let value): result.title = value
        }

        switch Self.field(raw, "artist", extract: { $0.stringValue }) {
        case .absent: break
        case .cleared: result.artist = nil
        case .value(let value): result.artist = value
        }

        switch Self.field(raw, "album", extract: { $0.stringValue }) {
        case .absent: break
        case .cleared: result.album = nil
        case .value(let value): result.album = value
        }

        switch Self.field(raw, "playing", extract: { $0.boolValue }) {
        case .absent: break
        case .cleared: result.isPlaying = false
        case .value(let value): result.isPlaying = value
        }

        switch Self.field(raw, "elapsedTime", extract: { $0.doubleValue }) {
        case .absent: break
        case .cleared: result.elapsed = nil
        case .value(let value): result.elapsed = value
        }

        switch Self.field(raw, "duration", extract: { $0.doubleValue }) {
        case .absent: break
        case .cleared: result.duration = nil
        case .value(let value): result.duration = value
        }

        switch Self.field(raw, "timestamp", extract: { $0.doubleValue }) {
        case .absent: break
        case .cleared: result.timestamp = nil
        case .value(let value): result.timestamp = Date(timeIntervalSince1970: value)
        }

        switch Self.field(raw, "playbackRate", extract: { $0.doubleValue }) {
        case .absent: break
        case .cleared: result.playbackRate = 1.0
        case .value(let value): result.playbackRate = value
        }

        switch Self.field(raw, "artworkData", extract: { $0.stringValue }) {
        case .absent: break
        case .cleared: result.artworkPNG = nil
        case .value(let base64): result.artworkPNG = Data(base64Encoded: base64)
        }

        // `parentApplicationBundleIdentifier` wins over `bundleIdentifier`
        // when both are present — a browser tab or a system extension is
        // reported under its host's bundle ID by the former.
        switch Self.field(raw, "bundleIdentifier", extract: { $0.stringValue }) {
        case .absent: break
        case .cleared: result.bundleIdentifier = nil
        case .value(let value): result.bundleIdentifier = value
        }
        switch Self.field(raw, "parentApplicationBundleIdentifier", extract: { $0.stringValue }) {
        case .absent: break
        case .cleared: break
        case .value(let value): result.bundleIdentifier = value
        }

        return result
    }
}

/// Estimates how far into the track playback actually is *right now*,
/// projecting forward from the last update rather than waiting for the next
/// one — the adapter only pushes an update when something changes, not on
/// every tick of a running clock.
public enum NowPlayingProgress {
    public static func elapsed(_ state: NowPlayingState, at now: Date) -> TimeInterval? {
        guard let baseElapsed = state.elapsed else { return nil }
        guard state.isPlaying, let timestamp = state.timestamp else {
            // Paused, or no timestamp to project from — the last reported
            // value is all there is.
            return baseElapsed
        }

        let projected = baseElapsed + now.timeIntervalSince(timestamp) * state.playbackRate
        if let duration = state.duration {
            return min(max(0, projected), duration)
        }
        return max(0, projected)
    }
}
