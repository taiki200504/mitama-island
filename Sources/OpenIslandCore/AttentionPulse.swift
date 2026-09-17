import Foundation

/// How long anything on the always-on island is allowed to keep pulsing for
/// attention before it settles and holds still.
///
/// A pulse that never stops costs CPU for as long as the thing it announces
/// sits there — an approval left over lunch, a song playing all afternoon —
/// and stops being noticed after the first few seconds anyway. It restarts
/// whenever what it announces changes.
public enum AttentionPulse {
    public static let duration: TimeInterval = 12

    /// Whole cycles of a `period`-second animation that fit in `duration`,
    /// at least one. For a Core Animation `repeatCount`.
    public static func repeatCount(period: TimeInterval) -> Float {
        guard period > 0 else { return 1 }
        return Float(max(1, (duration / period).rounded(.down)))
    }
}

/// What the menu bar icon shows: the most pressing thing across every session.
public enum StatusIconState: Equatable, Sendable {
    /// Nothing running, nothing waiting.
    case idle
    /// At least one session working.
    case running
    /// At least one session waiting on an approval or an answer.
    case attention

    public init(attentionCount: Int, runningCount: Int) {
        if attentionCount > 0 {
            self = .attention
        } else if runningCount > 0 {
            self = .running
        } else {
            self = .idle
        }
    }
}
