import Foundation

/// 今日出す復習カード1枚。`mos_learn_cards` は canon から役職 learn が毎朝作る派生物で、
/// 島は表と裏を読むだけ——覚えた／忘れたの記録（FSRS の状態）には触らない。
public struct MitamaLearnCard: Equatable, Sendable {
    public let domain: String
    public let front: String
    public let back: String
    /// 実務のどこで効くか。これが書けない知識はカードにしない、という契約になっている。
    public let why: String?

    public init(domain: String, front: String, back: String, why: String?) {
        self.domain = domain
        self.front = front
        self.back = back
        self.why = why
    }
}

/// 放置した画面に出すものを取ってくる口。読むだけ。
///
/// 通知の60秒ループには乗せない。盤面は1時間ごとにしか変わらず、カードは1日1枚で
/// 足りるので、毎分引くのは同じ答えを取りに行くだけになる。呼ぶのは画面を出す直前。
public struct MitamaAmbientClient: Sendable {
    /// 同じ答えを取りに行かないための間隔。盤面の更新が1時間ごとなので、
    /// 放置画面が何度出ても、この間は前に取ったものを使う。
    public static let freshness: TimeInterval = 10 * 60

    private let environment: MitamaEnvironment
    private let session: URLSession

    public init(environment: MitamaEnvironment, session: URLSession = .shared) {
        self.environment = environment
        self.session = session
    }

    /// 脈と今日の1枚。読めなかったものは黙って欠ける——放置画面は時計として
    /// 成立していればよく、数字が出ないことを謝る画面にはしない。
    public func fetch(
        weekStart: Date,
        now: Date = .now
    ) async -> (pulse: MitamaPulse, card: MitamaLearnCard?) {
        async let board = board()
        async let schedules = schedules()
        async let heartbeat = lastHeartbeat()
        async let card = learnCard(now: now)
        async let week = MitamaWorkLogClient(environment: environment, session: session)
            .weekSoFar(since: weekStart)

        let counted = await week
        let pulse = await MitamaPulse.make(
            board: board,
            schedules: schedules,
            lastHeartbeatAt: heartbeat,
            weekSessions: counted?.sessions ?? 0,
            weekSeconds: counted?.seconds ?? 0,
            now: now
        )
        return (pulse, await card)
    }

    // MARK: - 一本ずつ

    func board() async -> MitamaBoard? {
        guard let rows = await rows(
            "mos_daily_board",
            [URLQueryItem(name: "select", value: "*"), URLQueryItem(name: "limit", value: "1")]
        ), let row = rows.first else { return nil }

        return MitamaBoard(
            decisionsPending: row["decisions_pending"] as? Int ?? 0,
            decisionsOverdue: row["decisions_overdue"] as? Int ?? 0,
            tasksWithDue: row["tasks_with_due"] as? Int ?? 0,
            tasksOverdue: row["tasks_overdue"] as? Int ?? 0,
            inflow7d: row["inflow_7d"] as? Int ?? 0,
            done7d: row["done_7d"] as? Int ?? 0,
            error: row["error"] as? String,
            updatedAt: (row["updated_at"] as? String).flatMap(ISO8601Timestamp.parse)
        )
    }

    func schedules() async -> [MitamaSchedule] {
        guard let rows = await rows(
            "mos_schedules",
            [URLQueryItem(name: "select", value: "id,enabled,last_status,off_reason")]
        ) else { return [] }

        return rows.compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            return MitamaSchedule(
                id: id,
                enabled: row["enabled"] as? Bool ?? false,
                lastStatus: row["last_status"] as? String,
                offReason: row["off_reason"] as? String
            )
        }
    }

    /// 60秒ごとに1回打たれる鼓動の、最後の1つ。
    func lastHeartbeat() async -> Date? {
        let rows = await rows(
            "mos_execution_events",
            [
                URLQueryItem(name: "select", value: "created_at"),
                URLQueryItem(name: "type", value: "eq.heartbeat"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        return (rows?.first?["created_at"] as? String).flatMap(ISO8601Timestamp.parse)
    }

    /// 期限の来たカードのうち、一番長く待っている1枚。
    func learnCard(now: Date) async -> MitamaLearnCard? {
        // 時刻は必ず Z 終わりで組む。`+00:00` のまま query に載せると `+` が
        // 空白に化けて、PostgREST が 400 を返す。
        let deadline = ISO8601Timestamp.string(from: now)
        guard let rows = await rows(
            "mos_learn_cards",
            [
                URLQueryItem(name: "select", value: "domain,front,back,why"),
                URLQueryItem(name: "suspended", value: "eq.false"),
                URLQueryItem(name: "due", value: "lte.\(deadline)"),
                URLQueryItem(name: "order", value: "due.asc"),
                URLQueryItem(name: "limit", value: "1"),
            ]
        ), let row = rows.first,
           let domain = row["domain"] as? String,
           let front = row["front"] as? String,
           let back = row["back"] as? String else { return nil }

        return MitamaLearnCard(domain: domain, front: front, back: back, why: row["why"] as? String)
    }

    private func rows(_ table: String, _ queryItems: [URLQueryItem]) async -> [[String: Any]]? {
        guard let url = environment.endpoint(table, queryItems: queryItems),
              let (data, response) = try? await session.data(for: environment.authorized(URLRequest(url: url))),
              let status = (response as? HTTPURLResponse)?.statusCode,
              (200..<300).contains(status) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    }
}
