import Foundation

/// Recognises the one thing you have to say to start the sequence.
///
/// Kept apart from `VoiceCommandParser` even though both read speech. That one
/// answers permission prompts, where a wrong reading makes an agent act; this
/// one plays an animation. Different consequences deserve different vocabulary,
/// and mixing them would let a phrase drift from the harmless list into the
/// dangerous one.
public enum LinkstartPhrase: Sendable {
    /// Whether the speech contains the phrase, in any of the ways a recogniser
    /// is likely to write it down.
    public static func isSpoken(in text: String) -> Bool {
        let normalised = normalise(text)
        guard !normalised.isEmpty else { return false }
        return spellings.contains { normalised.contains($0) }
    }

    /// Speech recognisers break the phrase in different places and pick between
    /// kana and kanji-adjacent forms, so this matches on the joined-up spelling
    /// after separators are removed rather than trying to list every split.
    private static let spellings: Set<String> = [
        "リンクスタート",
        "りんくすたーと",
        "リンクスタト",
        "linkstart",
    ]

    private static func normalise(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .unicodeScalars
            .filter { !removedScalars.contains($0) }
            .map(String.init)
            .joined()
    }

    /// Separators only. Anything that carries sound stays.
    private static let removedScalars: Set<Unicode.Scalar> = [
        " ", "\u{3000}", ".", ",", "!", "?", "-", "–", "—",
        "、", "。", "！", "？", "・", "「", "」",
    ]
}
