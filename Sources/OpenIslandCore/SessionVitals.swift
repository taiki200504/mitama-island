import Foundation

/// A session's health while it waits on you: full when the request has just
/// arrived, draining the longer nobody answers it.
///
/// The same reading the closed island's gauge gives, put where the list can
/// use it too — one row per waiting agent, each with its own bar, so a glance
/// says who has been left longest rather than only that someone has.
public enum SessionVitals: Sendable {
    /// How the bar reads, for the colour the view picks.
    public enum Band: Equatable, Sendable {
        /// Just asked, or under ten minutes in.
        case fresh
        /// Over ten minutes.
        case overdue
        /// An hour or more.
        case critical
    }

    /// Never fully empty: a bar at zero reads as "gone", and the session is
    /// still there waiting.
    public static let floor = 0.15

    public static func hp(waitingFor seconds: TimeInterval) -> (fraction: Double, band: Band) {
        let elapsed = IslandPeekBand.elapsed(since: Date(timeIntervalSince1970: 0), now: Date(timeIntervalSince1970: max(seconds, 0)))
        switch elapsed {
        case .justNow:
            return (1, .fresh)
        case let .minutes(minutes):
            return (max(0.2, 1 - Double(minutes) / 30), minutes < 10 ? .fresh : .overdue)
        case .hours:
            return (floor, .critical)
        }
    }
}
