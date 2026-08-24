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
    public enum Elapsed: Equatable, Sendable {
        case justNow
        case minutes(Int)
        case hours(Int)
    }

    public struct Content: Equatable, Sendable {
        /// `CLAUDE`, `CODEX` — the tool, not the session title. A session title
        /// is arbitrary length, and truncating it beside a physical notch
        /// leaves a word fragment that means nothing.
        public let agent: String
        public let phase: SessionPhase
        public let elapsed: Elapsed
        /// Sessions waiting behind this one. Zero when this is the only one.
        public let othersWaiting: Int

        public init(agent: String, phase: SessionPhase, elapsed: Elapsed, othersWaiting: Int) {
            self.agent = agent
            self.phase = phase
            self.elapsed = elapsed
            self.othersWaiting = othersWaiting
        }
    }

    /// Nil when nothing is waiting — the island stays as it was.
    ///
    /// The session shown is the one that has been waiting **longest**. Showing
    /// the newest would mean the request you have already ignored twice keeps
    /// being pushed off the band by fresher ones.
    public static func content(for sessions: [AgentSession], now: Date = .now) -> Content? {
        let waiting = sessions.filter { $0.phase.requiresAttention }
        guard let oldest = waiting.min(by: { $0.updatedAt < $1.updatedAt }) else { return nil }

        return Content(
            agent: oldest.tool.shortName,
            phase: oldest.phase,
            elapsed: elapsed(since: oldest.updatedAt, now: now),
            othersWaiting: waiting.count - 1
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
