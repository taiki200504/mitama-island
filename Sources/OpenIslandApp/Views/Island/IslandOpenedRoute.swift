import Foundation
import OpenIslandCore

/// What the opened island should show first.
///
/// Decided once, from *why* the island opened, rather than re-derived from
/// whatever state happens to be current when the view renders — the same
/// `notification` reason looks different depending on whether a session ID
/// came with it, and a hand gesture wants to point at something the other
/// open reasons never do.
enum IslandOpenedRoute: Equatable {
    /// A single session's card, front and centre.
    case notificationCard(sessionID: String)
    /// The ordinary list. `highlight`, when set, is the row that should
    /// briefly ring to say "this is the one that summoned you".
    case sessionList(highlight: String?)
    /// The keyboard switcher, reusing the expanded panel.
    case switcher
    /// The moment right after launch, before there is anything to show yet.
    case bootSplash
}

enum IslandOpenedRouting {
    static func route(
        reason: NotchOpenReason?,
        surface: IslandSurface,
        firstActionableID: String?
    ) -> IslandOpenedRoute {
        switch reason {
        case .notification:
            guard let sessionID = surface.sessionID else {
                return .sessionList(highlight: nil)
            }
            return .notificationCard(sessionID: sessionID)
        case .switcher:
            return .switcher
        case .boot:
            return .bootSplash
        case .handGesture:
            return .sessionList(highlight: firstActionableID)
        case .click, .hover, .none:
            return .sessionList(highlight: nil)
        }
    }
}

extension IslandPanelView {
    /// What this open of the island should lead with.
    var openedRoute: IslandOpenedRoute {
        IslandOpenedRouting.route(
            reason: model.notchOpenReason,
            surface: model.islandSurface,
            firstActionableID: model.islandListSessions.first(where: \.phase.requiresAttention)?.id
        )
    }

    /// Non-nil only when a hand gesture opened the island and pointed at a
    /// session — the one row that should draw a brief ring.
    var gestureHighlightSessionID: String? {
        guard case let .sessionList(highlight) = openedRoute else { return nil }
        return highlight
    }
}
