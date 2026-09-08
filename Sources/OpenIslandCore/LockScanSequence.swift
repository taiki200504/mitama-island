import Foundation

/// Where the unlock greeting is at a given moment.
///
/// A presentation, not a security check: macOS has already unlocked the
/// screen by the time any of this runs. Nothing here authenticates anyone.
public enum LockScanPhase: Equatable, Sendable {
    /// The ring is still filling in.
    case scanning
    /// The ring has landed; the check glyph shows.
    case confirmed
    /// The check gives way to sitting on the name.
    case greeting
    /// Past the sequence's own duration — nothing left to draw.
    case done
}

/// The timing of the closed-island unlock greeting, as a pure function of
/// elapsed time — same discipline as `LinkstartSequence`: a dropped frame
/// changes how this *looks*, never where it *is*, because the view asks what
/// time it is rather than counting steps it has already drawn.
public enum LockScanSequence: Sendable {
    /// Total run time, matching `IslandSneakPeekKind.lockScan`'s duration in
    /// `IslandSneakPeekPolicy` — that policy reads this value rather than
    /// carrying a second copy of it.
    public static let duration: TimeInterval = 2.2

    /// When the ring finishes and the check glyph appears.
    public static let confirmedAt: TimeInterval = 0.6
    /// When the check gives way to sitting on the name.
    public static let greetingAt: TimeInterval = 1.4

    public static func phase(at elapsed: TimeInterval) -> LockScanPhase {
        if elapsed < confirmedAt { return .scanning }
        if elapsed < greetingAt { return .confirmed }
        if elapsed < duration { return .greeting }
        return .done
    }

    /// 0...1, eased out, over the scanning window; held at 1 for the rest of
    /// the sequence so the ring never runs backwards once it has landed.
    public static func ringProgress(at elapsed: TimeInterval) -> Double {
        let t = min(max(elapsed / confirmedAt, 0), 1)
        return 1 - pow(1 - t, 3)
    }
}
