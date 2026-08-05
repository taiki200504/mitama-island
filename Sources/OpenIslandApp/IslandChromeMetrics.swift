import CoreGraphics

enum IslandChromeMetrics {
    static let openedShadowHorizontalInset: CGFloat = 18
    static let openedShadowBottomInset: CGFloat = 22
    static let closedShadowHorizontalInset: CGFloat = 12
    static let closedShadowBottomInset: CGFloat = 14
    static let closedHoverScale: CGFloat = 1.028

    /// How tall the scrolling list of question options may grow.
    ///
    /// Shared with `OverlayPanelController` on purpose: the panel sizes itself
    /// from an estimate, and if the estimate and the scroll cap disagree the
    /// submit button ends up outside the panel — which is exactly the bug that
    /// made a long question unanswerable from the island.
    ///
    static let questionOptionListMaxHeight: CGFloat = 260

    /// How tall a notification card may grow before it scrolls as a whole.
    ///
    /// The backstop for the panel getting its own height slightly wrong: past
    /// this the card scrolls, so nothing inside it can be out of reach.
    static let notificationContentMaxHeight: CGFloat = 520
}
