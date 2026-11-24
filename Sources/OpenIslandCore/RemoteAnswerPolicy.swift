import Foundation

/// Answers from the phone must never widen what a single tap on the Mac would grant.
/// Mirrors mitama-os `escalationOption.ts`; keep the two lists in sync.
public enum RemoteAnswerPolicy {
    private static let patterns: [NSRegularExpression] = [
        "常に|いつも許可|常時",
        "今後は?聞かな|二度と聞かな|もう聞かな",
        "(すべて|全て|全部|一括).{0,4}(許可|承認|ok)",
        "権限モード|フルアクセス",
        "\\balways\\b",
        "don'?t ask again|do not ask again|never ask",
        "allow all|approve all|accept all|allow everything",
        "bypass|auto-?accept|accept ?edits|full access|yolo|dangerously",
        "セッション中|このセッション|このプロジェクト|以降|今後|自動で?(許可|承認)|自動承認|確認なしで|確認しない",
        "for (this|the) (session|project|rest)|from now on|auto ?mode|without asking",
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    public static func isEscalation(_ label: String) -> Bool {
        var text = label.precomposedStringWithCompatibilityMapping.lowercased()
        for quote in ["’", "‘", "`"] { text = text.replacingOccurrences(of: quote, with: "'") }
        let range = NSRange(text.startIndex..., in: text)
        return patterns.contains { $0.firstMatch(in: text, range: range) != nil }
    }
}
