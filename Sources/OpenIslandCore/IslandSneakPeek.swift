import Foundation

/// How urgent a sneak peek is. A higher kind interrupts a lower one; the
/// raw values are the priority, not a display order.
public enum IslandSneakPeekKind: Int, Comparable, Hashable, Sendable {
    case shelf = 10
    case trackChanged = 20
    case eventStarting = 30
    case timerDone = 40
    case lockScan = 50
    case hudGauge = 60

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A temporary message on the closed island: "the timer finished", "now
/// playing changed", a lock-scan animation. It never grows the island — only
/// the peek band's text and icon are replaced for as long as `until` says.
public struct IslandSneakPeek: Equatable, Hashable, Sendable {
    public let kind: IslandSneakPeekKind
    public let text: String
    /// An SF Symbol name.
    public let icon: String
    /// 0...1 when the peek is showing a gauge (the HUD gauge kind); nil
    /// otherwise.
    public let gauge: Double?
    public let until: Date

    public init(kind: IslandSneakPeekKind, text: String, icon: String, gauge: Double? = nil, until: Date) {
        self.kind = kind
        self.text = text
        self.icon = icon
        self.gauge = gauge
        self.until = until
    }
}

/// Decides which sneak peek wins when two want the island at once, and how
/// long each one gets.
///
/// A lower-priority peek arriving while a higher one is showing is dropped —
/// except `timerDone`, which is the one interruption worth a second try: it
/// means a timer someone set has actually finished, and losing that
/// announcement to a three-bar visualiser update is a worse trade than making
/// it wait a couple of seconds. The caller keeps the one dropped `timerDone`
/// in a pending slot and re-offers it once the interrupting peek expires.
public enum IslandSneakPeekPolicy {
    public static func duration(for kind: IslandSneakPeekKind) -> TimeInterval {
        switch kind {
        case .hudGauge: 1.2
        case .lockScan: LockScanSequence.duration
        case .timerDone: 4
        case .eventStarting: 4
        case .trackChanged: 1.8
        case .shelf: 1.2
        }
    }

    public static func expired(_ peek: IslandSneakPeek?, now: Date) -> Bool {
        guard let peek else { return true }
        return now >= peek.until
    }

    /// What should be showing after `candidate` arrives. Returns `current`
    /// unchanged when the candidate loses; returns `candidate` when it wins
    /// (including whenever nothing was showing, or the one showing had
    /// already expired).
    public static func replace(current: IslandSneakPeek?, with candidate: IslandSneakPeek, now: Date) -> IslandSneakPeek? {
        guard let current, !expired(current, now: now) else {
            return candidate
        }
        guard candidate.kind >= current.kind else {
            return current
        }
        return candidate
    }
}
