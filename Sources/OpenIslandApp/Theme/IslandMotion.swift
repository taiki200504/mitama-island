import AppKit
import SwiftUI

/// Every named motion value the island uses, in one place.
///
/// Before this, the same handful of curves (a 0.38/0.8 spring, a
/// 0.4,0,0.2,1 timing curve, a bare `.easeInOut(duration: 0.28)`) were
/// retyped at each call site with no name tying them together — changing
/// "how the island opens" meant grepping for numbers instead of editing one
/// declaration. Read `resolved(_:)` / `pure(reduces:_:)` rather than the raw
/// constants whenever the animation reaches the screen: Reduce Motion has to
/// win over every one of these, and checking that by hand at each call site
/// is exactly the kind of thing that gets forgotten once.
enum IslandMotion {
    // MARK: Notch state

    static let open = Animation.interactiveSpring(duration: 0.35, extraBounce: 0.20)
    static let close = Animation.smooth(duration: 0.15)
    static let pop = Animation.interactiveSpring(duration: 0.50, extraBounce: 0.25, blendDuration: 0.125)

    // MARK: Closed-pill content

    /// The closed pill resizing as its label, right slot or peek band change.
    static let bandChange = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.45)

    // MARK: Hover and selection

    static let hover = Animation.spring(response: 0.38, dampingFraction: 0.80)
    /// The one-shot highlight sweep across a button when the pointer lands.
    static let selectionSweep = Animation.easeOut(duration: 0.15)
    /// The outline flash on press.
    static let glowPulse = Animation.easeInOut(duration: 0.15)
    /// A session row settling into its new look after `session.phase` changes.
    static let rowPhase = Animation.easeInOut(duration: 0.28)

    // MARK: Modal content

    static let modalIn = Animation.interactiveSpring(duration: 0.30, extraBounce: 0.15)
    static let modalOut = Animation.easeIn(duration: 0.18)

    /// How long `OverlayUICoordinator.notchPop()` holds the popped state
    /// before folding back to closed.
    static let popHold: TimeInterval = 0.3

    /// True while the user has System Settings' Reduce Motion switch on.
    static var reducesMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// `animation`, unless the *current* system setting asks for less motion,
    /// in which case a short plain fade takes its place.
    static func resolved(_ animation: Animation) -> Animation {
        pure(reduces: reducesMotion, animation)
    }

    /// Same decision as `resolved(_:)`, with the setting passed in rather
    /// than read live — the form a test can actually call.
    static func pure(reduces: Bool, _ animation: Animation) -> Animation {
        reduces ? .easeOut(duration: 0.12) : animation
    }
}
