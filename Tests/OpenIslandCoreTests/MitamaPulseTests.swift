import Foundation
import Testing
@testable import OpenIslandCore

/// 放置画面に出す mitama の脈。守っているのは「何を異常と呼ばないか」。
struct MitamaPulseTests {
    private let now = Date(timeIntervalSince1970: 1_758_441_600)

    private func board(
        decisionsOverdue: Int = 0,
        tasksOverdue: Int = 0,
        inflow: Int = 3,
        done: Int = 3,
        error: String? = nil
    ) -> MitamaBoard {
        MitamaBoard(
            decisionsPending: 0,
            decisionsOverdue: decisionsOverdue,
            tasksWithDue: 2,
            tasksOverdue: tasksOverdue,
            inflow7d: inflow,
            done7d: done,
            error: error,
            updatedAt: now.addingTimeInterval(-1200)
        )
    }

    private func schedule(
        _ id: String,
        enabled: Bool = true,
        lastStatus: String? = "success",
        offReason: String? = nil
    ) -> MitamaSchedule {
        MitamaSchedule(id: id, enabled: enabled, lastStatus: lastStatus, offReason: offReason)
    }

    private func pulse(
        board: MitamaBoard? = nil,
        schedules: [MitamaSchedule] = [],
        heartbeatAgo: TimeInterval? = 30
    ) -> MitamaPulse {
        MitamaPulse.make(
            board: board,
            schedules: schedules,
            lastHeartbeatAt: heartbeatAgo.map { now.addingTimeInterval(-$0) },
            now: now
        )
    }

    // MARK: - 何を異常と呼ばないか

    /// 本人が意図して止めたものは異常ではない。ここを混ぜると、止めたはずの
    /// ものを毎日「障害」として出し続けることになる（2026-08-15 の就活の件）。
    @Test
    func aScheduleStoppedOnPurposeIsNotAFault() {
        let stopped = schedule("jobhunt-morning", enabled: false, lastStatus: "error", offReason: "本人が停止")
        #expect(stopped.isFailing == false)

        let result = pulse(board: board(), schedules: [stopped, schedule("butler-morning")])
        #expect(result.concern == nil)
        // 止めたものは「動いている本数」にも数えない。
        #expect(result.activeSchedules == 1)
    }

    @Test
    func aQuietBoardReportsNoConcern() {
        #expect(pulse(board: board(), schedules: [schedule("a"), schedule("b")]).concern == nil)
    }

    /// 鼓動は60秒ごと。1回や2回の取りこぼしで「死んだ」と言わない。
    @Test
    func aRecentHeartbeatIsNotSilence() {
        #expect(pulse(board: board(), heartbeatAgo: 90).concern == nil)
        #expect(pulse(board: board(), heartbeatAgo: 301).concern == .orchestratorSilent(minutes: 5))
    }

    /// 鼓動を一度も読めなかったときは、黙って「異常なし」にする——読めないことと
    /// 止まっていることは違う。
    @Test
    func anUnreadHeartbeatIsNotAFault() {
        #expect(pulse(board: board(), heartbeatAgo: nil).concern == nil)
    }

    // MARK: - 重い順に1つだけ

    @Test
    func theBoardsOwnErrorOutranksEverything() {
        let result = MitamaPulse.make(
            board: board(decisionsOverdue: 3, error: " 集計に失敗 "),
            schedules: [schedule("x", lastStatus: "error")],
            lastHeartbeatAt: now.addingTimeInterval(-9999),
            now: now
        )
        #expect(result.concern == .boardError("集計に失敗"))
    }

    @Test
    func aFailingScheduleOutranksSilenceAndOverdue() {
        let result = MitamaPulse.make(
            board: board(decisionsOverdue: 3),
            schedules: [schedule("voice-morning", lastStatus: "error"), schedule("b", lastStatus: "error")],
            lastHeartbeatAt: now.addingTimeInterval(-9999),
            now: now
        )
        #expect(result.concern == .scheduleFailing(id: "voice-morning", others: 1))
    }

    @Test
    func overdueIsTheLastThingLeft() {
        #expect(pulse(board: board(decisionsOverdue: 1, tasksOverdue: 2)).concern
            == .overdue(decisions: 1, tasks: 2))
    }

    /// 盤面が読めなくても描ける。数字は0でも、画面は時計として成立する。
    @Test
    func aMissingBoardStillMakesAPulse() {
        let result = pulse(board: nil, schedules: [schedule("a")])
        #expect(result.concern == nil)
        #expect(result.inflow7d == 0)
        #expect(result.asOf == nil)
    }

    // MARK: - 行動量

    /// 稼働があるのに 0.0h と出ると、やっていないことになる。
    @Test
    func aShortWeekNeverRoundsToZero() {
        let worked = MitamaPulse.make(
            board: nil, schedules: [], lastHeartbeatAt: nil,
            weekSessions: 1, weekSeconds: 60, now: now
        )
        #expect(worked.weekHours == 0.1)

        let idle = MitamaPulse.make(
            board: nil, schedules: [], lastHeartbeatAt: nil,
            weekSessions: 0, weekSeconds: 0, now: now
        )
        #expect(idle.weekHours == 0)
    }

    @Test
    func theWeekIsRoundedToOneDecimal() {
        let result = MitamaPulse.make(
            board: nil, schedules: [], lastHeartbeatAt: nil,
            weekSessions: 12, weekSeconds: 23_040, now: now
        )
        #expect(result.weekHours == 6.4)
    }
}
