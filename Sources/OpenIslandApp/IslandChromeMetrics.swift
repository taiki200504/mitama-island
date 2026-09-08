import CoreGraphics

enum IslandChromeMetrics {
    static let openedShadowHorizontalInset: CGFloat = 18
    static let openedShadowBottomInset: CGFloat = 22
    static let closedShadowHorizontalInset: CGFloat = 12
    static let closedShadowBottomInset: CGFloat = 14
    static let closedHoverScale: CGFloat = 1.028

    /// How tall the scrolling list of question options may grow.
    ///
    /// Shared with `OverlayPanelController` on purpose: the panel's *size*
    /// still comes from the estimate below, and the panel's *hit rectangle*
    /// (see `OverlayPanelController.interactiveRect`) comes from whichever is
    /// larger of that same estimate and the SwiftUI-measured content height
    /// (`AppModel.openedSurfaceMeasuredHeight`) — the estimate is the floor
    /// for both, the measurement is the source of truth for hit-testing once
    /// it exists. If the estimate and the scroll cap disagree, the submit
    /// button ends up outside the panel — which is exactly the bug that made
    /// a long question unanswerable from the island.
    ///
    static let questionOptionListMaxHeight: CGFloat = 260

    /// How tall a notification card may grow before it scrolls as a whole.
    ///
    /// The backstop for the panel getting its own height slightly wrong: past
    /// this the card scrolls, so nothing inside it can be out of reach.
    static let notificationContentMaxHeight: CGFloat = 520

    // MARK: - Floating pill (non-notched displays, closed island)

    /// Height of the closed capsule on a display with no physical notch.
    /// Independent of `NSScreen.islandClosedHeight` (which mirrors the menu
    /// bar's reserved height) — the capsule floats below the menu bar
    /// instead of sitting flush against the physical top edge, so nothing
    /// ties its height to that measurement anymore.
    static let floatingPillHeight: CGFloat = 30
    /// Gap between the floating capsule's top edge and the menu bar's
    /// bottom edge.
    static let floatingPillGap: CGFloat = 6
    /// Corner radius for the opened surface's top corners on a non-notched
    /// display, replacing the notch profile's concave cut.
    static let floatingPillOpenedTopRadius: CGFloat = 12
    /// Minimum width of the floating capsule and its hit area.
    static let floatingPillMinWidth: CGFloat = 96
    /// Extra hit-area padding added per side to the capsule's measured
    /// content width, so a click just past the visible pill edge still
    /// registers.
    static let floatingPillHitPadding: CGFloat = 12
}
