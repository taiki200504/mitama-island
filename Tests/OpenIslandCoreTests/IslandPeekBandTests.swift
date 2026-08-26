import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Closed-island peek band")
struct IslandPeekBandTests {
    private let epoch = Date(timeIntervalSince1970: 1_000_000)

    private func session(
        _ id: String,
        tool: AgentTool = .claudeCode,
        phase: SessionPhase,
        waitingFor seconds: TimeInterval = 0
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: id,
            tool: tool,
            phase: phase,
            summary: "",
            updatedAt: epoch.addingTimeInterval(-seconds)
        )
    }

    @Test("Nothing waiting means no band")
    func quietIslandStaysQuiet() {
        let sessions = [
            session("a", phase: .running),
            session("b", phase: .completed),
        ]
        #expect(IslandPeekBand.content(for: sessions, now: epoch) == nil)
    }

    @Test("No sessions at all means no band")
    func emptyIslandStaysQuiet() {
        #expect(IslandPeekBand.content(for: [], now: epoch) == nil)
    }

    @Test("One waiting session names the agent and how long")
    func singleWaiter() {
        let sessions = [
            session("busy", phase: .running),
            session("asking", tool: .codex, phase: .waitingForApproval, waitingFor: 120),
        ]
        let content = IslandPeekBand.content(for: sessions, now: epoch)
        #expect(content?.agent == "CODEX")
        #expect(content?.subject == .session(.waitingForApproval))
        #expect(content?.elapsed == .minutes(2))
        #expect(content?.othersWaiting == 0)
    }

    @Test("The one waiting longest wins, and the rest are counted")
    func oldestWaiterWins() {
        let sessions = [
            session("fresh", phase: .waitingForAnswer, waitingFor: 30),
            session("stale", tool: .geminiCLI, phase: .waitingForApproval, waitingFor: 3_600),
            session("middle", phase: .waitingForAnswer, waitingFor: 600),
        ]
        let content = IslandPeekBand.content(for: sessions, now: epoch)
        // Newest-first would push the request already ignored twice off the band.
        #expect(content?.agent == "GEMINI")
        #expect(content?.elapsed == .hours(1))
        #expect(content?.othersWaiting == 2)
    }

    @Test("Running and completed sessions never count as others waiting")
    func onlyWaitingSessionsAreCounted() {
        let sessions = [
            session("asking", phase: .waitingForApproval, waitingFor: 60),
            session("busy1", phase: .running),
            session("busy2", phase: .running),
            session("done", phase: .completed),
        ]
        #expect(IslandPeekBand.content(for: sessions, now: epoch)?.othersWaiting == 0)
    }

    private func alert(
        _ id: Int,
        level: MitamaNotification.Level = .urgent,
        createdAgo seconds: TimeInterval = 0
    ) -> MitamaNotification {
        MitamaNotification(
            id: id,
            level: level,
            title: "title \(id)",
            body: "",
            createdAt: epoch.addingTimeInterval(-seconds)
        )
    }

    @Test("A mitama urgent takes the band even when an agent has waited longer")
    func urgentOutranksAgents() {
        let sessions = [session("asking", tool: .codex, phase: .waitingForApproval, waitingFor: 3_600)]
        let content = IslandPeekBand.content(
            for: sessions,
            mitamaAlerts: [alert(1, createdAgo: 120)],
            now: epoch
        )
        // The agent already announced itself with a card; the mitama row did not.
        #expect(content?.agent == "MITAMA")
        #expect(content?.subject == .mitamaAlert)
        #expect(content?.elapsed == .minutes(2))
        #expect(content?.othersWaiting == 1)
    }

    @Test("Homework is a list to work through, not an interruption")
    func homeworkStaysOffTheBand() {
        #expect(
            IslandPeekBand.content(
                for: [],
                mitamaAlerts: [alert(1, level: .homework), alert(2, level: .digest), alert(3, level: .info)],
                now: epoch
            ) == nil
        )
    }

    @Test("Homework never inflates the count of what is waiting")
    func homeworkIsNotCounted() {
        let sessions = [session("asking", phase: .waitingForApproval, waitingFor: 60)]
        let content = IslandPeekBand.content(
            for: sessions,
            mitamaAlerts: [alert(1, level: .homework), alert(2, level: .homework)],
            now: epoch
        )
        #expect(content?.subject == .session(.waitingForApproval))
        #expect(content?.othersWaiting == 0)
    }

    @Test("The oldest urgent wins, and the rest are counted")
    func oldestUrgentWins() {
        let content = IslandPeekBand.content(
            for: [],
            mitamaAlerts: [alert(1, createdAgo: 60), alert(2, createdAgo: 7_200)],
            now: epoch
        )
        #expect(content?.elapsed == .hours(2))
        #expect(content?.othersWaiting == 1)
    }

    @Test("An urgent alone is enough for a band")
    func urgentWithoutAnySession() {
        let content = IslandPeekBand.content(for: [], mitamaAlerts: [alert(1, createdAgo: 300)], now: epoch)
        #expect(content?.agent == "MITAMA")
        #expect(content?.othersWaiting == 0)
    }

    @Test("Under a minute reads as just now, not as zero minutes")
    func subMinuteIsJustNow() {
        #expect(IslandPeekBand.elapsed(since: epoch, now: epoch) == .justNow)
        #expect(IslandPeekBand.elapsed(since: epoch.addingTimeInterval(-59), now: epoch) == .justNow)
    }

    @Test("Minutes and hours turn over at the boundary, not near it")
    func unitBoundaries() {
        func elapsed(_ seconds: TimeInterval) -> IslandPeekBand.Elapsed {
            IslandPeekBand.elapsed(since: epoch.addingTimeInterval(-seconds), now: epoch)
        }
        #expect(elapsed(60) == .minutes(1))
        #expect(elapsed(3_599) == .minutes(59))
        #expect(elapsed(3_600) == .hours(1))
        #expect(elapsed(90_000) == .hours(25))
    }

    @Test("A clock that jumped backwards does not read as a long wait")
    func futureStampIsJustNow() {
        #expect(IslandPeekBand.elapsed(since: epoch.addingTimeInterval(600), now: epoch) == .justNow)
    }
}
