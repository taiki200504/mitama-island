import CoreGraphics

enum IslandChromeMetrics {
    static let openedShadowHorizontalInset: CGFloat = 18
    static let openedShadowBottomInset: CGFloat = 22
    static let closedShadowHorizontalInset: CGFloat = 12
    static let closedShadowBottomInset: CGFloat = 14
    static let closedHoverScale: CGFloat = 1.028

    /// How tall a notification card may grow before it scrolls as a whole.
    ///
    /// The backstop for the panel getting its own height slightly wrong: past
    /// this the card scrolls, so nothing inside it can be out of reach.
    static let notificationContentMaxHeight: CGFloat = 520
    static let notificationContentPadding: CGFloat = 48

    static func notificationViewportHeight(maxPanelHeight: CGFloat, availableHeight: CGFloat = .greatestFiniteMagnitude) -> CGFloat {
        max(0, min(notificationContentMaxHeight, maxPanelHeight - notificationContentPadding, availableHeight))
    }

    static func scrollViewportHeight(contentHeight: CGFloat, maxHeight: CGFloat) -> CGFloat {
        let cap = max(0, maxHeight)
        return contentHeight > 0 ? min(contentHeight, cap) : cap
    }

    // MARK: - Floating pill (non-notched displays, closed island)

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
