import Foundation

/// 全画面を奪った演出を、いつから入力で閉じてよいか。
///
/// 画面ぜんぶを覆うものは、どのキーでも閉じられないといけない。ただし
/// **始まった直後だけは別**で、そこで閉じるのはたいてい本人の意思ではない:
/// 画面を突然奪われた反射で Esc を叩く、演出を呼んだキーの余りが届く、
/// 自動操作が打った鍵が回り込む。実測でも、19 秒の演出が毎回 1.5 秒で
/// 消えていた原因はこれだった。
///
/// 猶予は 1 秒まで。これ以上伸ばすと、逃げ道を塞ぐ側に回る。
public enum OverlayDismissGate: Sendable {
    /// 猶予の上限。呼ぶ側が何を渡してもここで頭打ちにする。
    public static let maximumGrace: TimeInterval = 1.0

    /// `presentedAt` に出したものを、`now` の入力で閉じてよいか。
    public static func allowsDismiss(
        presentedAt: Date,
        now: Date,
        grace: TimeInterval
    ) -> Bool {
        now.timeIntervalSince(presentedAt) >= min(max(grace, 0), maximumGrace)
    }
}
