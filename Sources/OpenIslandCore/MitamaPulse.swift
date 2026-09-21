import Foundation

/// `mos_daily_board` の1行。mitama が1時間ごとに上書きする会社の盤面。
public struct MitamaBoard: Equatable, Sendable {
    public let decisionsPending: Int
    public let decisionsOverdue: Int
    public let tasksWithDue: Int
    public let tasksOverdue: Int
    public let inflow7d: Int
    public let done7d: Int
    /// 盤面を作る側が自分で気づいた異常。null が正常。
    public let error: String?
    public let updatedAt: Date?

    public init(
        decisionsPending: Int,
        decisionsOverdue: Int,
        tasksWithDue: Int,
        tasksOverdue: Int,
        inflow7d: Int,
        done7d: Int,
        error: String?,
        updatedAt: Date?
    ) {
        self.decisionsPending = decisionsPending
        self.decisionsOverdue = decisionsOverdue
        self.tasksWithDue = tasksWithDue
        self.tasksOverdue = tasksOverdue
        self.inflow7d = inflow7d
        self.done7d = done7d
        self.error = error
        self.updatedAt = updatedAt
    }
}

/// `mos_schedules` の1行のうち、止まっているかを見るのに要る分だけ。
public struct MitamaSchedule: Equatable, Sendable {
    public let id: String
    public let enabled: Bool
    public let lastStatus: String?
    /// 意図的に止めた理由。空でないなら「止まっている」のではなく「止めた」。
    public let offReason: String?

    public init(id: String, enabled: Bool, lastStatus: String?, offReason: String?) {
        self.id = id
        self.enabled = enabled
        self.lastStatus = lastStatus
        self.offReason = offReason
    }

    /// 直すべき異常かどうか。`off_reason` のある行は数えない（051_schedule_off_reason.sql）
    /// ——ここを混ぜると、本人が止めたものを「障害」として毎日出すことになる。
    public var isFailing: Bool {
        enabled && offReason == nil && lastStatus == "error"
    }
}

/// 放置した画面に出す、mitama の脈。
///
/// 閉じた島にも新しい面にも出さない。席を外しているときだけ出るので、島が
/// 自分から何か言う量は増えない。数えるのは「直すべき異常」だけで、本人が
/// 意図して止めたものは異常に数えない。
public struct MitamaPulse: Equatable, Sendable {
    /// 出すのは一番重いもの1つだけ。並べると読む壁になる。
    public enum Concern: Equatable, Sendable {
        /// 盤面を作る側が自分で気づいた異常。
        case boardError(String)
        /// 止まっている定期実行。`others` は同じ状態の残り。
        case scheduleFailing(id: String, others: Int)
        /// orchestrator の鼓動が途切れている。
        case orchestratorSilent(minutes: Int)
        /// 期限を過ぎたまま残っているもの。
        case overdue(decisions: Int, tasks: Int)
    }

    /// 鼓動が来なくなったと見なすまで。実機は60秒ごとに1回打つ。
    public static let heartbeatSilence: TimeInterval = 5 * 60

    /// nil は「異常なし」。
    public let concern: Concern?
    /// 動いている定期実行の本数。異常が無いときに出す唯一の数字。
    public let activeSchedules: Int
    public let inflow7d: Int
    public let done7d: Int
    /// 今週の稼働。島が唯一まっすぐ測れる行動量。
    public let weekSessions: Int
    public let weekSeconds: Int
    /// 盤面が最後に書かれた時刻。1時間ごとの更新なので、古さを隠さずに出す。
    public let asOf: Date?

    public init(
        concern: Concern?,
        activeSchedules: Int,
        inflow7d: Int,
        done7d: Int,
        weekSessions: Int,
        weekSeconds: Int,
        asOf: Date?
    ) {
        self.concern = concern
        self.activeSchedules = activeSchedules
        self.inflow7d = inflow7d
        self.done7d = done7d
        self.weekSessions = weekSessions
        self.weekSeconds = weekSeconds
        self.asOf = asOf
    }

    /// 重い順に1つだけ拾う。盤面が自分で気づいた異常 → 止まっている定期実行 →
    /// 鼓動の途絶 → 期限切れ。どれも無ければ nil。
    public static func make(
        board: MitamaBoard?,
        schedules: [MitamaSchedule],
        lastHeartbeatAt: Date?,
        weekSessions: Int = 0,
        weekSeconds: Int = 0,
        now: Date = .now
    ) -> MitamaPulse {
        let failing = schedules.filter(\.isFailing)
        let active = schedules.filter { $0.enabled && $0.offReason == nil }.count

        let concern: Concern?
        if let error = board?.error, !error.trimmed.isEmpty {
            concern = .boardError(error.trimmed)
        } else if let first = failing.first {
            concern = .scheduleFailing(id: first.id, others: failing.count - 1)
        } else if let beat = lastHeartbeatAt, now.timeIntervalSince(beat) > heartbeatSilence {
            concern = .orchestratorSilent(minutes: Int(now.timeIntervalSince(beat) / 60))
        } else if let board, board.decisionsOverdue + board.tasksOverdue > 0 {
            concern = .overdue(decisions: board.decisionsOverdue, tasks: board.tasksOverdue)
        } else {
            concern = nil
        }

        return MitamaPulse(
            concern: concern,
            activeSchedules: active,
            inflow7d: board?.inflow7d ?? 0,
            done7d: board?.done7d ?? 0,
            weekSessions: weekSessions,
            weekSeconds: weekSeconds,
            asOf: board?.updatedAt
        )
    }

    /// 今週の稼働を「6.4」のような時間にする。分を丸めるので、0 より大きい
    /// 稼働が 0.0h と出ることはない。
    public var weekHours: Double {
        guard weekSeconds > 0 else { return 0 }
        return max(0.1, (Double(weekSeconds) / 3600 * 10).rounded() / 10)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
