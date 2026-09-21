import Foundation

/// RSI（毎朝 07:00 に ~/.claude を1つ直す自己改善）が出した、本人に判断を求める1件。
public struct MitamaProposal: Equatable, Sendable, Identifiable {
    /// 提案が最初に出た日。`mos_rsi_runs` の主キーで、返事を書き戻す先でもある。
    public let runDate: String
    public let text: String
    /// 最初に出た日から数えた経過日数。7日を越えると RSI が毎朝 urgent で催促する。
    public let ageDays: Int

    public var id: String { "\(runDate)\u{1F}\(text)" }

    public init(runDate: String, text: String, ageDays: Int) {
        self.runDate = runDate
        self.text = text
        self.ageDays = ageDays
    }
}

/// `mos_rsi_runs` の1行のうち、提案の生死を決めるのに要る分だけ。
public struct MitamaRSIRun: Equatable, Sendable {
    public let runDate: String
    /// Hub や島から「やる／捨てる」が返っているか。
    public let hasReply: Bool
    /// その日の枠A・枠Bが出した提案の本文。
    public let proposals: [String]
    /// その日に RSI 自身が消化した提案の本文。
    public let resolved: [String]

    public init(runDate: String, hasReply: Bool, proposals: [String], resolved: [String]) {
        self.runDate = runDate
        self.hasReply = hasReply
        self.proposals = proposals
        self.resolved = resolved
    }
}

/// まだ返事の付いていない提案。
///
/// 判定は RSI 側の `~/.claude/rsi/collect.py` の `open_proposals()` と同じ規則に
/// している。解決の記録は2経路しかない——本人が「やる／捨てる」を返したか、RSI 自身が
/// 消化したか——ので、どちらも無いものだけが残る。空文字にしても消えないのは、
/// 2026-09-07 にそれで課題6件中5件が黙って消えた側の作りだから。
public enum MitamaProposalBacklog {
    /// 島が一度に出す数。3件を越えると「読む壁」になって、押されないまま溜まる。
    public static let displayLimit = 3

    /// 古い順。同じ本文が何日も出ていたら、最初に出た日のものだけを残す——
    /// 返事はその日の行に書き戻すので、拾う日を間違えると催促が止まらない。
    public static func open(
        from rows: [MitamaRSIRun],
        now: Date,
        calendar: Calendar = .current,
        limit: Int = displayLimit
    ) -> [MitamaProposal] {
        let resolved = Set(rows.flatMap(\.resolved).map { $0.trimmed }).subtracting([""])
        let answered = Set(
            rows.filter(\.hasReply).flatMap(\.proposals).map { $0.trimmed }
        ).subtracting([""])

        var seen: Set<String> = []
        var open: [MitamaProposal] = []

        for run in rows.sorted(by: { $0.runDate < $1.runDate }) {
            for raw in run.proposals {
                let text = raw.trimmed
                guard !text.isEmpty,
                      !resolved.contains(text),
                      !answered.contains(text),
                      seen.insert(text).inserted else { continue }
                open.append(
                    MitamaProposal(
                        runDate: run.runDate,
                        text: text,
                        ageDays: ageInDays(from: run.runDate, to: now, calendar: calendar)
                    )
                )
            }
        }

        return Array(open.prefix(limit))
    }

    /// `YYYY-MM-DD` から今日までの日数。読めない日付は 0 にして、古さを偽らない。
    static func ageInDays(from runDate: String, to now: Date, calendar: Calendar) -> Int {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        guard let start = formatter.date(from: runDate) else { return 0 }
        let days = calendar.dateComponents([.day], from: start, to: now).day ?? 0
        return max(0, days)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// `mos_rsi_runs` を読むだけの口。書き戻しは `MitamaWorkLogClient.perform` が持つ——
/// 何を起こしてよいかの判断を、読む側に散らさないため。
public struct MitamaProposalClient: Sendable {
    /// 遡る日数。RSI は1日1行しか書かないので、これで2か月分になる。
    private static let rowLimit = 60

    private let environment: MitamaEnvironment
    private let session: URLSession

    public init(environment: MitamaEnvironment, session: URLSession = .shared) {
        self.environment = environment
        self.session = session
    }

    /// 返事待ちの提案を古い順に。読めなければ空——島は黙って描き続ける。
    public func openProposals(now: Date = Date()) async -> [MitamaProposal] {
        guard let url = environment.endpoint(
            "mos_rsi_runs",
            queryItems: [
                URLQueryItem(name: "select", value: "run_date,proposal_reply,slot_a,slot_b"),
                URLQueryItem(name: "order", value: "run_date.desc"),
                URLQueryItem(name: "limit", value: "\(Self.rowLimit)"),
            ]
        ) else { return [] }

        guard let (data, response) = try? await session.data(for: environment.authorized(URLRequest(url: url))),
              let status = (response as? HTTPURLResponse)?.statusCode,
              (200..<300).contains(status),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return MitamaProposalBacklog.open(from: rows.compactMap(Self.run(from:)), now: now)
    }

    /// 枠A・枠Bの生ログをそのまま入れてある jsonb から、提案の生死に要る分だけ取り出す。
    /// RSI 側のプロンプト構造が変わっても列を増やさずに済むよう jsonb にしてあるので、
    /// 欠けている鍵は「無い」として扱い、行ごと捨てない。
    static func run(from row: [String: Any]) -> MitamaRSIRun? {
        guard let runDate = row["run_date"] as? String else { return nil }

        let slots = ["slot_a", "slot_b"].compactMap { row[$0] as? [String: Any] }
        return MitamaRSIRun(
            runDate: runDate,
            hasReply: row["proposal_reply"] is String,
            proposals: slots.compactMap { $0["proposal"] as? String },
            resolved: slots.flatMap { ($0["resolved_proposals"] as? [String]) ?? [] }
        )
    }
}
