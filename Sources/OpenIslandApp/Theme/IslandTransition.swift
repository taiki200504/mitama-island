import SwiftUI

/// Reveals content by masking it with a rectangle that grows from nothing to
/// full width from the leading edge, while the content itself settles down
/// from a small vertical offset — a panel being wiped open rather than
/// faded or scaled in.
struct WidthWipe: ViewModifier, @MainActor Animatable {
    /// 0 = fully masked away, 1 = fully revealed.
    var progress: CGFloat
    /// How far the content still has to travel vertically into place.
    var yOffset: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(progress, yOffset) }
        set { (progress, yOffset) = (newValue.first, newValue.second) }
    }

    func body(content: Content) -> some View {
        content
            .offset(y: yOffset)
            .mask(alignment: .leading) {
                GeometryReader { geometry in
                    Rectangle().frame(width: max(0, geometry.size.width * progress))
                }
            }
    }
}

/// Scales content along a single axis from its own centre — a view growing
/// or shrinking in place, as opposed to sliding into new space.
struct AxisScale: ViewModifier, @MainActor Animatable {
    enum Axis {
        case vertical
        case horizontal
    }

    var scale: CGFloat
    var axis: Axis

    var animatableData: CGFloat {
        get { scale }
        set { scale = newValue }
    }

    func body(content: Content) -> some View {
        switch axis {
        case .vertical:
            content.scaleEffect(x: 1, y: scale, anchor: .center)
        case .horizontal:
            content.scaleEffect(x: scale, y: 1, anchor: .center)
        }
    }
}

/// Named enter/exit transitions for a whole element appearing or
/// disappearing — as opposed to `IslandMotion`, which covers a value
/// changing while the view stays put.
///
/// Computed rather than stored: `AnyTransition` isn't `Sendable`, so a
/// stored `static let` would need to promise there is only ever one copy of
/// it shared safely — a computed property sidesteps that by simply building
/// a fresh value each time, which is all a `View` body ever does with it
/// anyway.
@MainActor
enum IslandTransition {
    /// A card sliding open from the leading edge. For anything that drops
    /// onto the opened surface on its own — an approval, a question, a
    /// completion notice, a hint banner.
    static var panelDrop: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: WidthWipe(progress: 0, yOffset: -12),
                identity: WidthWipe(progress: 1, yOffset: 0)
            ),
            removal: .modifier(
                active: WidthWipe(progress: 0, yOffset: -6),
                identity: WidthWipe(progress: 1, yOffset: 0)
            )
        )
    }

    /// Content scaling in from its own centre — for a view that replaces
    /// itself in place rather than sliding into new space: a row's embedded
    /// detail body opening, one prompt layout swapping for another.
    static var modal: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: AxisScale(scale: 0.02, axis: .vertical),
                identity: AxisScale(scale: 1, axis: .vertical)
            ),
            removal: .modifier(
                active: AxisScale(scale: 0.05, axis: .horizontal),
                identity: AxisScale(scale: 1, axis: .horizontal)
            )
        )
    }

    /// `transition`, unless Reduce Motion is on, in which case a plain fade
    /// takes its place — the same escape hatch `IslandMotion.resolved(_:)`
    /// gives the continuous animations.
    static func resolved(_ transition: AnyTransition) -> AnyTransition {
        IslandMotion.reducesMotion ? .opacity : transition
    }
}
