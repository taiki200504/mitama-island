import Foundation
import Testing
@testable import OpenIslandCore

/// 返事待ちの提案。RSI 側の `collect.py open_proposals()` と同じ答えになることが要件。
struct MitamaProposalTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    /// 2026-09-21 の正午。経過日数を数えるので、時計ではなく暦から作る。
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 12))!
    }

    private func run(
        _ date: String,
        reply: Bool = false,
        proposals: [String] = [],
        resolved: [String] = []
    ) -> MitamaRSIRun {
        MitamaRSIRun(runDate: date, hasReply: reply, proposals: proposals, resolved: resolved)
    }

    private func open(_ rows: [MitamaRSIRun], limit: Int = MitamaProposalBacklog.displayLimit) -> [MitamaProposal] {
        MitamaProposalBacklog.open(from: rows, now: now, calendar: calendar, limit: limit)
    }

    @Test
    func aProposalWithNoAnswerStaysOpen() {
        #expect(open([run("2026-09-01", proposals: ["gstack を消してよいか"])]).map(\.text)
            == ["gstack を消してよいか"])
    }

    /// 解決の記録は2経路しかない。どちらかが立てば消える。
    @Test
    func anAnsweredOrSelfResolvedProposalDisappears() {
        let answered = open([run("2026-09-01", reply: true, proposals: ["答えた"])])
        #expect(answered.isEmpty)

        let selfResolved = open([
            run("2026-09-01", proposals: ["RSI が自分で消化した"]),
            run("2026-09-05", resolved: ["RSI が自分で消化した"]),
        ])
        #expect(selfResolved.isEmpty)
    }

    /// 同じ提案が何日も出る。返事は最初に出た日の行に書き戻すので、
    /// 拾う日を間違えると催促が止まらない。
    @Test
    func aRepeatedProposalKeepsItsFirstDay() {
        let rows = [
            run("2026-09-05", proposals: ["同じ話"]),
            run("2026-09-01", proposals: ["同じ話"]),
            run("2026-09-03", proposals: ["同じ話"]),
        ]

        let proposals = open(rows)
        #expect(proposals.count == 1)
        #expect(proposals.first?.runDate == "2026-09-01")
    }

    /// 「最古30日」と催促されているものが、島でも30日に見えること。
    @Test
    func theAgeIsCountedFromTheFirstDay() {
        #expect(open([run("2026-08-22", proposals: ["30日前の話"])]).first?.ageDays == 30)
    }

    /// 空文字にしても消えない。2026-09-07 まではこれで課題が黙って消えていた。
    @Test
    func anEmptyProposalIsNotAProposal() {
        #expect(open([run("2026-09-01", proposals: ["", "   "])]).isEmpty)
    }

    @Test
    func theOldestComeFirstAndTheListIsCapped() {
        let rows = (1...6).map { run(String(format: "2026-09-%02d", $0), proposals: ["提案\($0)"]) }

        let proposals = open(rows)
        #expect(proposals.count == MitamaProposalBacklog.displayLimit)
        #expect(proposals.map(\.text) == ["提案1", "提案2", "提案3"])
    }

    // MARK: - 行の読み取り

    /// 枠の中身は RSI 側のプロンプト構造ごと jsonb に入っている。鍵が欠けていても
    /// 行ごと捨てない——捨てると、その日の提案が二度と出てこない。
    @Test
    func aRowWithHalfTheSlotsStillReadsItsProposal() {
        let row = MitamaProposalClient.run(from: [
            "run_date": "2026-09-01",
            "proposal_reply": NSNull(),
            "slot_a": ["proposal": "枠Aの話"],
        ])

        #expect(row?.runDate == "2026-09-01")
        #expect(row?.hasReply == false)
        #expect(row?.proposals == ["枠Aの話"])
    }

    @Test
    func aRowWithoutADateIsSkipped() {
        #expect(MitamaProposalClient.run(from: ["slot_a": ["proposal": "日付が無い"]]) == nil)
    }

    @Test
    func aReplyOnTheRowMarksItAnswered() {
        let row = MitamaProposalClient.run(from: [
            "run_date": "2026-09-01",
            "proposal_reply": "drop",
            "slot_a": ["proposal": "捨てた話", "resolved_proposals": ["別の話"]],
        ])

        #expect(row?.hasReply == true)
        #expect(row?.resolved == ["別の話"])
    }
}
