import Foundation
import Testing
@testable import OpenIslandCore

@Suite struct AmbientBoardTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(
        _ id: String,
        phase: SessionPhase = .waitingForApproval,
        minutesAgo: Double
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: id,
            tool: .claudeCode,
            phase: phase,
            summary: "",
            updatedAt: now.addingTimeInterval(-minutesAgo * 60)
        )
    }

    private func waiting(_ id: String, minutesAgo: Double) -> AgentSession {
        session(id, minutesAgo: minutesAgo)
    }

    private func alert(_ title: String, minutesAgo: Double) -> MitamaNotification {
        MitamaNotification(
            id: Int(minutesAgo),
            level: .urgent,
            title: title,
            body: "",
            createdAt: now.addingTimeInterval(-minutesAgo * 60)
        )
    }

    @Test func anIdleMachineWithNothingWaitingIsJustAClock() {
        let board = AmbientBoard.make(for: [], now: now)
        #expect(board.isQuiet)
        #expect(board.hiddenCount == 0)
    }

    /// The request already ignored twice must not be pushed down the screen by
    /// fresher ones.
    @Test func longestWaitingComesFirst() {
        let board = AmbientBoard.make(
            for: [waiting("new", minutesAgo: 2), waiting("old", minutesAgo: 90), waiting("mid", minutesAgo: 30)],
            now: now
        )
        #expect(board.waiting.count == 3)
        #expect(board.waiting.first?.elapsed == .hours(1))
    }

    @Test func onlySessionsThatActuallyWantSomethingAppear() {
        let running = session("running", phase: .running, minutesAgo: 5)
        let board = AmbientBoard.make(for: [running, waiting("asks", minutesAgo: 5)], now: now)
        #expect(board.waiting.count == 1)
    }

    /// Past four rows it stops being glanceable and starts being a backlog.
    @Test func overflowIsCountedRatherThanListed() {
        let sessions = (0 ..< 7).map { waiting("s\($0)", minutesAgo: Double($0 + 1)) }
        let board = AmbientBoard.make(for: sessions, now: now)
        #expect(board.waiting.count == AmbientBoard.maximumWaitingRows)
        #expect(board.hiddenCount == 3)
    }

    @Test func newestAlertsFirstAndCappedAtTwo() {
        let board = AmbientBoard.make(
            for: [],
            mitamaAlerts: [alert("古い", minutesAgo: 300), alert("新しい", minutesAgo: 5), alert("中", minutesAgo: 60)],
            now: now
        )
        #expect(board.alerts == ["新しい", "中"])
        #expect(board.hiddenCount == 1)
        #expect(board.isQuiet == false)
    }

    @Test func onlyUrgentRowsInterruptAnIdleScreen() {
        let homework = MitamaNotification(id: 1, level: .homework, title: "宿題", body: "", createdAt: now)
        let board = AmbientBoard.make(for: [], mitamaAlerts: [homework], now: now)
        #expect(board.isQuiet)
    }
}
