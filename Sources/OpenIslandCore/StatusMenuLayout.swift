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

    public init(
        isMuted: Bool,
        cameraIsWatching: Bool,
        shelfItemNames: [String],
        waitingCount: Int
    ) {
        self.isMuted = isMuted
        self.cameraIsWatching = cameraIsWatching
        self.shelfItemNames = shelfItemNames
        self.waitingCount = waitingCount
    }
}

/// One row (or separator) in the status item menu, in display order.
public enum StatusMenuEntry: Equatable, Sendable {
    case openIsland(waitingCount: Int)
    case toggleMute(isMuted: Bool)
    case toggleCamera(isWatching: Bool)
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
