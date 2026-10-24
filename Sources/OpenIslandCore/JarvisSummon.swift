import Foundation

/// 「ジャービス」の呼びかけで Raphael.app が出す分散通知の中身。
///
/// 分散通知は同じユーザーの別プロセスからも出せる。だから島は「開いて状態を1行出す」だけに使い、
/// 受付・承認・送信の権限は持たない。中身は依頼IDと固定の状態語だけ（本文・予定・秘密は載らない）。
/// 決まった形でなければ丸ごと捨てる。
public struct JarvisSummon: Sendable, Equatable {
    public static let notificationName = "dev.mitama.island.jarvis.summon"

    /// 送り手（Raphael.app）での意味:
    /// - listening: 呼びかけを聞き取った／聞き取りに戻った
    /// - acking: 起動語だけへの声の返事（「はい。ご用件をどうぞ」）。確認カードの表示ではない
    /// - running: 受付印がある依頼を照合している（カードの押下待ちは含めない）
    /// - done: owner 画面で完了を検証できた時だけ
    /// - failed: 失敗・取り消し・検証できない完了・結果不明
    public enum State: String, Sendable, CaseIterable {
        case listening, acking, running, done, failed

        /// 結果が出た状態。
        public var isTerminal: Bool { self == .done || self == .failed }

        /// 1行を出したままにする状態。受付済みの照合中だけで、それ以外はしばらくして下げる
        /// （次の状態が来ないまま「聞いています」が残り続けないように）。
        public var persists: Bool { self == .running }

        /// 島を開く状態。呼びかけた時と結果が出た時だけ開き、途中の状態は1行を書き換えるだけにする
        /// （本人が途中で閉じた島を何度も開け直さない）。
        public var opensIsland: Bool { self == .listening || isTerminal }
    }

    /// 呼びかけの直後はまだ依頼IDが無いので nil。
    public let requestID: UUID?
    public let state: State

    public init(requestID: UUID?, state: State) {
        self.requestID = requestID
        self.state = state
    }

    private static let allowedKeys: Set<String> = ["request", "state"]
    private static let maxRequestLength = 36

    /// userInfo を読む。キーは request・state の2つだけ、state は固定語、request は空か UUID。
    public static func parse(userInfo: [AnyHashable: Any]?) -> JarvisSummon? {
        guard let userInfo, userInfo.count == allowedKeys.count else { return nil }
        var fields: [String: String] = [:]
        for (key, value) in userInfo {
            guard let key = key as? String, allowedKeys.contains(key), let value = value as? String else { return nil }
            fields[key] = value
        }
        guard let rawState = fields["state"], let state = State(rawValue: rawState),
              let rawRequest = fields["request"], rawRequest.count <= maxRequestLength else { return nil }
        if rawRequest.isEmpty { return JarvisSummon(requestID: nil, state: state) }
        guard let id = UUID(uuidString: rawRequest) else { return nil }
        return JarvisSummon(requestID: id, state: state)
    }
}

/// 同じ通知が続けて届いた時に二度開かない。同じ依頼・同じ状態は `window` 秒の間だけ捨てる。
public struct JarvisSummonDeduper: Sendable {
    public let window: TimeInterval
    private var last: (summon: JarvisSummon, at: Date)?

    public init(window: TimeInterval = 5) {
        self.window = window
    }

    public mutating func accept(_ summon: JarvisSummon, at now: Date) -> Bool {
        if let last, last.summon == summon, now.timeIntervalSince(last.at) < window { return false }
        last = (summon, now)
        return true
    }
}
