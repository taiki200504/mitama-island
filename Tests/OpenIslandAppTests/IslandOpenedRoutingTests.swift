import Testing
@testable import OpenIslandApp
import OpenIslandCore

@Suite("Island opened routing")
struct IslandOpenedRoutingTests {
    private let surfaceWithSession = IslandSurface.sessionList(actionableSessionID: "s1")
    private let surfaceWithoutSession = IslandSurface.sessionList()

    @Test("A notification with a session ID leads with that session's card")
    func notificationWithSessionRoutesToCard() {
        let route = IslandOpenedRouting.route(
            reason: .notification,
            surface: surfaceWithSession,
            firstActionableID: "s2"
        )
        #expect(route == .notificationCard(sessionID: "s1"))
    }

    /// Should never happen in practice (nothing opens `.notification` without
    /// a session), but a route that would crash on that combination is worse
    /// than one that just falls back to the list.
    @Test("A notification with no session ID falls back to the list")
    func notificationWithoutSessionFallsBackToList() {
        let route = IslandOpenedRouting.route(
            reason: .notification,
            surface: surfaceWithoutSession,
            firstActionableID: nil
        )
        #expect(route == .sessionList(highlight: nil))
    }

    @Test("The switcher always wins its own route, regardless of surface")
    func switcherRoutesToSwitcher() {
        for surface in [surfaceWithSession, surfaceWithoutSession] {
            let route = IslandOpenedRouting.route(reason: .switcher, surface: surface, firstActionableID: "s2")
            #expect(route == .switcher)
        }
    }

    @Test("Boot always leads with the splash, regardless of surface")
    func bootRoutesToSplash() {
        for surface in [surfaceWithSession, surfaceWithoutSession] {
            let route = IslandOpenedRouting.route(reason: .boot, surface: surface, firstActionableID: nil)
            #expect(route == .bootSplash)
        }
    }

    @Test("A hand gesture highlights the first actionable session")
    func handGestureHighlightsFirstActionable() {
        let route = IslandOpenedRouting.route(
            reason: .handGesture,
            surface: surfaceWithoutSession,
            firstActionableID: "s7"
        )
        #expect(route == .sessionList(highlight: "s7"))
    }

    @Test("A hand gesture with nothing actionable highlights nothing")
    func handGestureWithNoActionableHighlightsNothing() {
        let route = IslandOpenedRouting.route(reason: .handGesture, surface: surfaceWithoutSession, firstActionableID: nil)
        #expect(route == .sessionList(highlight: nil))
    }

    @Test("Click routes to the plain list")
    func clickRoutesToPlainList() {
        let route = IslandOpenedRouting.route(reason: .click, surface: surfaceWithSession, firstActionableID: "s9")
        #expect(route == .sessionList(highlight: nil))
    }

    @Test("Hover routes to the plain list")
    func hoverRoutesToPlainList() {
        let route = IslandOpenedRouting.route(reason: .hover, surface: surfaceWithSession, firstActionableID: "s9")
        #expect(route == .sessionList(highlight: nil))
    }

    @Test("No reason at all still routes to the plain list")
    func noReasonRoutesToPlainList() {
        let route = IslandOpenedRouting.route(reason: nil, surface: surfaceWithSession, firstActionableID: "s9")
        #expect(route == .sessionList(highlight: nil))
    }
}
