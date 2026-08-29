import Foundation

/// What the machine shows while nobody is touching it.
///
/// An idle Mac spends its time on a wallpaper, which is the largest surface in
/// the room and says nothing. mitama's job is to have the next thing ready
/// rather than to hold it in a database, so the idle screen is where the
/// waiting work goes.
///
/// The whole decision is a function of the sessions, the alerts and the clock —
/// the view draws it and decides nothing.
public struct AmbientBoard: Equatable, Sendable {
    public struct WaitingRow: Equatable, Sendable {
        public let agent: String
        public let elapsed: IslandPeekBand.Elapsed

        public init(agent: String, elapsed: IslandPeekBand.Elapsed) {
            self.agent = agent
            self.elapsed = elapsed
        }
    }

    /// Who is waiting, longest first.
    public let waiting: [WaitingRow]
    /// mitama rows that asked to interrupt, newest first.
    public let alerts: [String]
    /// Everything that did not fit. Zero when the lists are complete.
    public let hiddenCount: Int

    /// A screen read from across a room, not a list to work through. Past four
    /// rows it stops being glanceable and starts being a backlog, which is the
    /// Hub's job.
    public static let maximumWaitingRows = 4
    /// Urgent rows are rare by construction. Two is enough to say "there is
    /// more than one" without turning the screen into a feed.
    public static let maximumAlerts = 2

    public init(waiting: [WaitingRow], alerts: [String], hiddenCount: Int) {
        self.waiting = waiting
        self.alerts = alerts
        self.hiddenCount = hiddenCount
    }

    /// True when there is nothing to report and the board is just a clock.
    public var isQuiet: Bool { waiting.isEmpty && alerts.isEmpty }

    public static func make(
        for sessions: [AgentSession],
        mitamaAlerts: [MitamaNotification] = [],
        now: Date = .now
    ) -> AmbientBoard {
        // Longest-waiting first, for the same reason the closed island's band
        // picks the oldest: the request already ignored twice must not be
        // pushed down the screen by fresher ones.
        let waitingSessions = sessions
            .filter { $0.phase.requiresAttention }
            .sorted { $0.updatedAt < $1.updatedAt }

        let urgent = mitamaAlerts
            .filter { $0.level == .urgent }
            .sorted { $0.createdAt > $1.createdAt }

        let shownWaiting = waitingSessions.prefix(maximumWaitingRows).map {
            WaitingRow(agent: $0.tool.shortName, elapsed: IslandPeekBand.elapsed(since: $0.updatedAt, now: now))
        }
        let shownAlerts = urgent.prefix(maximumAlerts).map(\.title)

        return AmbientBoard(
            waiting: Array(shownWaiting),
            alerts: Array(shownAlerts),
            hiddenCount: (waitingSessions.count - shownWaiting.count)
                + (urgent.count - shownAlerts.count)
        )
    }
}
