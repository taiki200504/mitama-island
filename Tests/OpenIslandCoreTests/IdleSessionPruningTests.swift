import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Idle session pruning")
struct IdleSessionPruningTests {
    private func session(
        id: String,
        phase: SessionPhase,
        updatedMinutesAgo: Double,
        now: Date
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: id,
            tool: .claudeCode,
            phase: phase,
            summary: "",
            updatedAt: now.addingTimeInterval(-updatedMinutesAgo * 60)
        )
    }

    private let now = Date(timeIntervalSince1970: 2_000_000)

    @Test("A settled session past the cutoff is dropped")
    func dropsStaleCompleted() {
        var state = SessionState(sessions: [
            session(id: "old", phase: .completed, updatedMinutesAgo: 180, now: now)
        ])
        #expect(state.pruneIdleSessions(olderThan: 7200, now: now) == ["old"])
        #expect(state.sessions.isEmpty)
    }

    @Test("A recent session stays")
    func keepsRecent() {
        var state = SessionState(sessions: [
            session(id: "fresh", phase: .completed, updatedMinutesAgo: 10, now: now)
        ])
        #expect(state.pruneIdleSessions(olderThan: 7200, now: now).isEmpty)
        #expect(state.sessions.count == 1)
    }

    /// The failure that would matter most: sweeping away the approval the user
    /// was about to answer. A blocked session is idle *because* it is waiting.
    @Test("A session waiting on the user is never dropped")
    func neverDropsBlocked() {
        var state = SessionState(sessions: [
            session(id: "approval", phase: .waitingForApproval, updatedMinutesAgo: 999, now: now),
            session(id: "question", phase: .waitingForAnswer, updatedMinutesAgo: 999, now: now)
        ])
        #expect(state.pruneIdleSessions(olderThan: 1800, now: now).isEmpty)
        #expect(state.sessions.count == 2)
    }

    @Test("A zero interval prunes nothing")
    func neverSetting() {
        var state = SessionState(sessions: [
            session(id: "old", phase: .completed, updatedMinutesAgo: 10_000, now: now)
        ])
        #expect(state.pruneIdleSessions(olderThan: 0, now: now).isEmpty)
    }
}
