import Foundation
import Observation

/// Whether Now Playing runs at all, whether the closed island shows it, and
/// whether a track change gets its own sneak peek.
final class NowPlayingSettings: PreferenceGroup {
    let registrar = ObservationRegistrar()
    let store: PreferenceStore

    init(store: PreferenceStore = .standard) {
        self.store = store
    }

    /// On by default: unlike the eye-break timer, Now Playing never
    /// interrupts anything on its own — it only ever reflects whatever is
    /// already playing, so there's no "surprised by a feature that started
    /// itself" moment to guard against.
    var enabled: Bool {
        get { read(\.enabled, Keys.enabled, true) }
        set { write(\.enabled, Keys.enabled, newValue) }
    }

    /// Whether the closed-island accessory (artwork + visualiser) shows up
    /// at all. Independent of `enabled` so a track can still be controlled
    /// from the opened surface and the menu bar without the closed pill
    /// changing shape every time something plays.
    var showsInClosedIsland: Bool {
        get { read(\.showsInClosedIsland, Keys.showsInClosedIsland, true) }
        set { write(\.showsInClosedIsland, Keys.showsInClosedIsland, newValue) }
    }

    /// Whether a track change gets a "♪ title — artist" sneak peek.
    var sneakPeekOnTrackChange: Bool {
        get { read(\.sneakPeekOnTrackChange, Keys.sneakPeekOnTrackChange, true) }
        set { write(\.sneakPeekOnTrackChange, Keys.sneakPeekOnTrackChange, newValue) }
    }
}

extension NowPlayingSettings {
    enum Keys {
        static let enabled = "nowPlaying.enabled"
        static let showsInClosedIsland = "nowPlaying.showsInClosedIsland"
        static let sneakPeekOnTrackChange = "nowPlaying.sneakPeekOnTrackChange"
    }
}
