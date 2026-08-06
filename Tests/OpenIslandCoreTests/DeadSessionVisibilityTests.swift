import Foundation
import Testing
@testable import OpenIslandCore

@Suite("A session whose process is gone")
struct DeadSessionVisibilityTests {
    private func hookSession(
        phase: SessionPhase,
        alive: Bool,
        ended: Bool = false
    ) -> AgentSession {
        var session = AgentSession(
            id: "s",
            title: "s",
            tool: .claudeCode,
            phase: phase,
            summary: "",
            updatedAt: .now
        )
        session.isHookManaged = true
        session.isProcessAlive = alive
        session.isSessionEnded = ended
        return session
    }

    /// The row that prompted this: the terminal was closed without the agent's
    /// end-of-session hook firing, so nothing ever marked the session over and it
    /// sat in the island as "completed" indefinitely.
    @Test("A finished session with no process is not shown")
    func hidesFinishedAndDead() {
        #expect(hookSession(phase: .completed, alive: false).isVisibleInIsland == false)
    }

    @Test("A finished session whose agent is still running is shown")
    func keepsFinishedAndAlive() {
        #expect(hookSession(phase: .completed, alive: true).isVisibleInIsland)
    }

    /// Process detection can miss. A running session that momentarily fails to
    /// match a process is still running, and hiding live work over one missed
    /// probe would be far worse than showing a row too many.
    @Test("A running session survives a missed process check")
    func keepsRunningEvenIfNotMatched() {
        #expect(hookSession(phase: .running, alive: false).isVisibleInIsland)
    }

    /// Anything waiting on the user outranks every other rule — it is the whole
    /// reason the island exists.
    @Test("A session waiting on the user is always shown")
    func alwaysKeepsBlocked() {
        #expect(hookSession(phase: .waitingForApproval, alive: false).isVisibleInIsland)
        #expect(hookSession(phase: .waitingForAnswer, alive: false).isVisibleInIsland)
    }

    @Test("A cleanly ended session is not shown")
    func hidesEnded() {
        #expect(hookSession(phase: .completed, alive: true, ended: true).isVisibleInIsland == false)
        #expect(hookSession(phase: .running, alive: true, ended: true).isVisibleInIsland == false)
    }

    /// Sessions the app found by looking at processes rather than through a hook
    /// were already governed by liveness. That must not change.
    @Test("A process-discovered session still follows its process")
    func nonHookSessionsUnchanged() {
        var session = hookSession(phase: .completed, alive: false)
        session.isHookManaged = false
        #expect(session.isVisibleInIsland == false)

        session.isProcessAlive = true
        #expect(session.isVisibleInIsland)
    }
}
