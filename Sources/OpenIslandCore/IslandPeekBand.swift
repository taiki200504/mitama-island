import Foundation

/// What the closed island says while something is waiting on you.
///
/// The closed island used to say only how many sessions exist — `×46` on a busy
/// machine, which answers a question nobody asked. Who is waiting, and for how
/// long, was readable only after opening the panel, and the notification that
/// announced it collapsed on its own. Miss it and the island was back to a
/// colour.
///
/// This is the whole decision, as a function of the sessions and the clock, so
/// the view has nothing left to decide.
public enum IslandPeekBand: Sendable {
    /// How long something has been waiting, in the coarsest unit that still
    /// says something useful. Seconds are deliberately absent: a band that
    /// reticks every second would redraw a background app sixty times a minute
    /// to tell you what "just now" already told you.
    public enum Elapsed: Equatable, Hashable, Sendable {
        case justNow
        case minutes(Int)
        case hours(Int)
    }

    /// What is doing the waiting. The band draws these differently because
    /// they ask for different things: an agent is paused mid-task, while
    /// mitama has already finished and needs a decision.
    public enum Subject: Equatable, Hashable, Sendable {
        case session(SessionPhase)
        case mitamaAlert
    }

    /// The name mitama's own row carries. Not a tool short name like the
    /// others, but it sits in the same slot and reads the same way.
    public static let mitamaLabel = "MITAMA"

    public struct Content: Equatable, Hashable, Sendable {
        /// `CLAUDE`, `CODEX` — the tool, not the session title.
        public let agent: String
        public let subject: Subject
        public let elapsed: Elapsed
        /// Everything else waiting behind this one. Zero when this is the only
        /// one.
        public let othersWaiting: Int
        /// A short label for whichever session is waiting, when the band is
        /// showing an agent row. Omitted for mitama alerts and calendar bodies
        /// — and on notched layouts, where the view drops it before drawing.
        public let sessionTitle: String?

        public init(
            agent: String,
            subject: Subject,
            elapsed: Elapsed,
            othersWaiting: Int,
            sessionTitle: String? = nil
        ) {
            self.agent = agent
            self.subject = subject
            self.elapsed = elapsed
            self.othersWaiting = othersWaiting
            self.sessionTitle = sessionTitle
        }
    }

    /// Long enough to tell sessions apart on an external display; the view
    /// truncates further when the pill is tight.
    public static let peekSessionTitleMaxLength = 28

    public static func shortSessionTitle(_ title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count > peekSessionTitleMaxLength else { return trimmed }
        let clipped = String(trimmed.prefix(peekSessionTitleMaxLength))
        if let lastSpace = clipped.lastIndex(of: " "),
           clipped.distance(from: clipped.startIndex, to: lastSpace) > peekSessionTitleMaxLength / 2 {
            return String(clipped[clipped.startIndex..<lastSpace]) + "…"
        }
        return clipped + "…"
    }

    /// Nil when nothing is waiting — the island stays as it was.
    ///
    /// The one shown is whichever has been waiting **longest**. Showing the
    /// newest would mean the request you have already ignored twice keeps
    /// being pushed off the band by fresher ones.
    ///
    /// A mitama alert outranks any waiting agent, and not because it matters
    /// more. An agent that needs an answer announces itself the moment it stops
    /// — a card, a sound, a session that visibly went quiet. mitama's urgent
    /// row lands in a database and says nothing, so the band is the only place
    /// it can be seen without opening something. `homework` stays out: it is
    /// a list to work through, not an interruption, and it belongs in the Hub.
    public static func content(
        for sessions: [AgentSession],
        mitamaAlerts: [MitamaNotification] = [],
        now: Date = .now
    ) -> Content? {
        let waiting = sessions.filter { $0.phase.requiresAttention }
        let urgent = mitamaAlerts.filter { $0.level == .urgent }
        let othersWaiting = waiting.count + urgent.count - 1

        if let oldest = urgent.min(by: { $0.createdAt < $1.createdAt }) {
            return Content(
                agent: mitamaLabel,
                subject: .mitamaAlert,
                elapsed: elapsed(since: oldest.createdAt, now: now),
                othersWaiting: othersWaiting
            )
        }

        guard let oldest = waiting.min(by: { $0.updatedAt < $1.updatedAt }) else { return nil }

        return Content(
            agent: oldest.tool.shortName,
            subject: .session(oldest.phase),
            elapsed: elapsed(since: oldest.updatedAt, now: now),
            othersWaiting: othersWaiting,
            sessionTitle: shortSessionTitle(oldest.title)
        )
    }

    /// A waiting session is blocked on the user, so nothing updates it and
    /// `updatedAt` stays put at the moment it started waiting. That makes it the
    /// waiting-since stamp already, and saves carrying a second date that could
    /// drift out of step with the first.
    public static func elapsed(since start: Date, now: Date = .now) -> Elapsed {
        let seconds = now.timeIntervalSince(start)
        guard seconds >= 60 else { return .justNow }

        let minutes = Int(seconds / 60)
        guard minutes >= 60 else { return .minutes(minutes) }

        return .hours(minutes / 60)
    }
}
