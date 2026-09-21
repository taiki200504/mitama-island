import Foundation

/// RSI が出した提案への返事。
///
/// `do` か `drop` の2値しかない。迷いを表す状態を増やすと「保留」が溜まり、
/// 督促が止まらなかった元の状態に戻る（053_rsi_proposal_reply.sql）。
public enum MitamaProposalReply: String, Sendable, CaseIterable {
    /// やる。
    case act = "do"
    /// 捨てる。
    case drop
}

/// 島から mitama に手を出せる行為。
///
/// 事前に本人の承認が要るのは金銭・法務・不可逆・対外の4つだけ、という取り決めが
/// ある（mitama-os の docs/PURPOSE.md）。島は常駐していて誤って触りやすいので、
/// その4つに当たる行為を**型として持たない**。ここに無いものは島から起こせない。
///
/// とくに定期実行は「止める」しか無い。2026-08-15 に本人が止めた就活の定期実行を、
/// 3日後に evolve が「4日間サイレント停止していた障害」と診断して勝手に戻した事故が
/// ある（051_schedule_off_reason.sql）。戻すのは理由を書ける場所でやることにして、
/// 島には `enabled = true` を作れる値を置かない。
public enum MitamaIslandAction: Equatable, Sendable {
    /// 定期実行を止める。理由は必須（空だと自己改善が勝手に戻す）。
    case stopSchedule(id: String, reason: String)
    /// RSI の提案に返事をする。`runDate` は `mos_rsi_runs` の主キー（YYYY-MM-DD）。
    case replyToProposal(runDate: String, reply: MitamaProposalReply)
    /// 思い付きを1行で置く。
    case note(String)

    /// 本文の上限。島から投げるのは一行メモなので、長い文章は Hub で書く。
    public static let noteLimit = 2_000
    /// 理由の上限。
    public static let reasonLimit = 500
}

public extension MitamaIslandAction {
    var table: String {
        switch self {
        case .stopSchedule: "mos_schedules"
        case .replyToProposal: "mos_rsi_runs"
        case .note: "mos_brain_notes"
        }
    }

    /// 既存の行を直すものは PATCH、足すものは POST。
    var method: String {
        switch self {
        case .stopSchedule, .replyToProposal: "PATCH"
        case .note: "POST"
        }
    }

    /// PATCH が当たる行を1つに絞り込む条件。POST では空。
    var filters: [URLQueryItem] {
        switch self {
        case let .stopSchedule(id, _):
            [URLQueryItem(name: "id", value: "eq.\(id)")]
        case let .replyToProposal(runDate, _):
            [URLQueryItem(name: "run_date", value: "eq.\(runDate)")]
        case .note:
            []
        }
    }

    /// 送る前に弾く。空の理由・空のメモ・宛先の無い更新はネットワークまで運ばない。
    var isValid: Bool {
        switch self {
        case let .stopSchedule(id, reason):
            !id.trimmed.isEmpty
                && !reason.trimmed.isEmpty
                && reason.count <= Self.reasonLimit
        case let .replyToProposal(runDate, _):
            Self.isRunDate(runDate)
        case let .note(body):
            !body.trimmed.isEmpty && body.count <= Self.noteLimit
        }
    }

    /// `now` は引数。ハーネスが任意の時刻を固定して描くので、時計を直接読まない。
    func body(now: Date) -> [String: Any] {
        let stamp = ISO8601Timestamp.string(from: now)
        switch self {
        case let .stopSchedule(_, reason):
            return [
                "enabled": false,
                "off_reason": reason.trimmed,
                "off_at": stamp,
            ]
        case let .replyToProposal(_, reply):
            return [
                "proposal_reply": reply.rawValue,
                "proposal_replied_at": stamp,
            ]
        case let .note(body):
            // `source` は 'mobile|cli|ai_chat|slack|import|book' の検査に縛られて
            // いて island が無い（014_second_brain.sql）。列を増やすほどの話では
            // ないので、出所は source_ref とタグで残す。
            return [
                "body": body.trimmed,
                "source": "cli",
                "source_ref": "island",
                "tags": ["island"],
            ]
        }
    }

    /// `mos_rsi_runs` の主キーは日付そのもの。ここを緩めると PATCH が広く当たる。
    private static func isRunDate(_ value: String) -> Bool {
        guard value.count == 10 else { return false }
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2 else { return false }
        return parts.allSatisfy { $0.allSatisfy(\.isNumber) }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
