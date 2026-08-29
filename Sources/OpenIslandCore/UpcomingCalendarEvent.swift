import Foundation

/// What the closed island says when nothing is waiting on you.
///
/// The band was blank in that state, which is most of the day. mitama's job is
/// to put the next deadline in front of the person rather than in a database,
/// and the calendar is the one source of deadlines that is already on the
/// machine — no API to stand up, no account to connect.
///
/// The whole decision lives here as a function of the events and the clock, so
/// the view and the EventKit layer have nothing left to decide.
public enum UpcomingCalendarEvent: Sendable {
    /// The parts of a calendar entry this needs. Deliberately not `EKEvent` —
    /// that type cannot be constructed in a test and drags EventKit into the
    /// core module.
    public struct Event: Equatable, Sendable {
        public let title: String
        public let startsAt: Date
        public let isAllDay: Bool

        public init(title: String, startsAt: Date, isAllDay: Bool) {
            self.title = title
            self.startsAt = startsAt
            self.isAllDay = isAllDay
        }
    }

    public struct Band: Equatable, Sendable {
        public let title: String
        public let startsAt: Date
        /// Whole minutes from now until it starts. Never negative.
        public let minutesUntil: Int
        /// Everything else inside the horizon, behind this one.
        public let othersAhead: Int

        public init(title: String, startsAt: Date, minutesUntil: Int, othersAhead: Int) {
            self.title = title
            self.startsAt = startsAt
            self.minutesUntil = minutesUntil
            self.othersAhead = othersAhead
        }
    }

    /// How far ahead is still worth calling "next".
    ///
    /// Eight hours covers a working day from its first hour. Beyond that the
    /// band would spend the evening counting down to tomorrow morning, which
    /// is a fact nobody needs at the moment it is shown and which would keep
    /// the pill lit all night.
    public static let horizon: TimeInterval = 8 * 3600

    /// Nil when nothing qualifies — the island stays as it was.
    ///
    /// All-day entries are skipped: "starts in 40 minutes" is not true of
    /// something that has no start time, and a birthday would sit on the band
    /// for the whole day it belongs to.
    public static func band(
        for events: [Event],
        now: Date = .now,
        horizon: TimeInterval = horizon
    ) -> Band? {
        let upcoming = events
            .filter { !$0.isAllDay }
            .filter { $0.startsAt > now }
            .filter { $0.startsAt.timeIntervalSince(now) <= horizon }
            .sorted { $0.startsAt < $1.startsAt }

        guard let next = upcoming.first else { return nil }

        return Band(
            title: next.title,
            startsAt: next.startsAt,
            // Rounded up, so a meeting 90 seconds away reads as 2 minutes
            // rather than as 1. Rounding down here would let the band say
            // "0 minutes" for the last full minute before it starts.
            minutesUntil: max(0, Int(ceil(next.startsAt.timeIntervalSince(now) / 60))),
            othersAhead: upcoming.count - 1
        )
    }
}
