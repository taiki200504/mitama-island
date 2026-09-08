import Foundation

/// What the menu bar's status item menu needs to know to draw itself.
///
/// A plain snapshot rather than a live reference to `AppModel` — the same
/// separation `AmbientBoard` and `IslandPeekBand` use, so the menu's shape can
/// be tested without standing up a real `NSStatusItem`.
public struct StatusMenuInputs: Sendable {
    public var isMuted: Bool
    public var cameraIsWatching: Bool
    public var shelfItemNames: [String]
    /// Sessions waiting on an approval or an answer right now.
    public var waitingCount: Int
    /// The running timer's label ("WORK", "REST", …), or `nil` while idle —
    /// nil is what decides whether the menu offers presets or a stop action.
    public var timerRunningLabel: String?
    /// Whether the clipboard history is switched on at all. Off by default,
    /// so the menu carries no clipboard row for anyone who never turned the
    /// feature on.
    public var clipboardIsEnabled: Bool
    /// What's playing, or `nil` while nothing is (or the adapter has no
    /// title to report yet) — nil is what hides the row entirely.
    public var nowPlayingTrack: NowPlayingTrack?

    public struct NowPlayingTrack: Equatable, Sendable {
        public var title: String
        public var isPlaying: Bool

        public init(title: String, isPlaying: Bool) {
            self.title = title
            self.isPlaying = isPlaying
        }
    }

    public init(
        isMuted: Bool,
        cameraIsWatching: Bool,
        shelfItemNames: [String],
        waitingCount: Int,
        timerRunningLabel: String? = nil,
        clipboardIsEnabled: Bool = false,
        nowPlayingTrack: NowPlayingTrack? = nil
    ) {
        self.isMuted = isMuted
        self.cameraIsWatching = cameraIsWatching
        self.shelfItemNames = shelfItemNames
        self.waitingCount = waitingCount
        self.timerRunningLabel = timerRunningLabel
        self.clipboardIsEnabled = clipboardIsEnabled
        self.nowPlayingTrack = nowPlayingTrack
    }
}

/// One row (or separator) in the status item menu, in display order.
public enum StatusMenuEntry: Equatable, Sendable {
    case openIsland(waitingCount: Int)
    case toggleMute(isMuted: Bool)
    case toggleCamera(isWatching: Bool)
    /// Idle: offers the fixed preset list as its own submenu.
    case startTimer(presets: [FocusTimerPreset])
    case timerRunning(label: String)
    case stopTimer
    case openClipboard
    case nowPlayingTrack(title: String, isPlaying: Bool)
    case shelfHeader(count: Int)
    case shelfItem(name: String)
    case clearShelf
    case separator
    case settings
    case quit
}

/// Turns `StatusMenuInputs` into the fixed sequence of rows the menu bar item
/// shows.
///
/// The reason this exists as pure data rather than living inside
/// `NSMenuDelegate.menuNeedsUpdate` directly: a menu built straight from
/// `AppModel` can only be checked by opening it, and a status item is one of
/// the few surfaces a headless harness run cannot screenshot.
public enum StatusMenuLayout {
    /// Rows shown before the shelf hands off to "and the rest are on the
    /// shelf" — the same ceiling the island's own list uses to stay
    /// glanceable rather than becoming a backlog.
    public static let maximumShelfItems = 5

    public static func entries(for inputs: StatusMenuInputs) -> [StatusMenuEntry] {
        var entries: [StatusMenuEntry] = [
            .openIsland(waitingCount: inputs.waitingCount),
            .toggleMute(isMuted: inputs.isMuted),
            .toggleCamera(isWatching: inputs.cameraIsWatching),
        ]

        if let label = inputs.timerRunningLabel {
            entries.append(.timerRunning(label: label))
            entries.append(.stopTimer)
        } else {
            entries.append(.startTimer(presets: FocusTimerPreset.allCases))
        }

        if inputs.clipboardIsEnabled {
            entries.append(.openClipboard)
        }

        if let track = inputs.nowPlayingTrack {
            entries.append(.nowPlayingTrack(title: track.title, isPlaying: track.isPlaying))
        }

        if !inputs.shelfItemNames.isEmpty {
            entries.append(.separator)
            entries.append(.shelfHeader(count: inputs.shelfItemNames.count))
            entries.append(contentsOf: inputs.shelfItemNames.prefix(maximumShelfItems).map(StatusMenuEntry.shelfItem))
            entries.append(.clearShelf)
        }

        entries.append(.separator)
        entries.append(.settings)
        entries.append(.quit)

        return entries
    }
}
