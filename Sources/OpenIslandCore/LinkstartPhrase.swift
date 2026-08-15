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
    ///
    /// Matched as two halves rather than as finished spellings. A Japanese
    /// recogniser writes the loanword in whichever script it likes and mixes
    /// them freely — the first real utterance came back as "Linkスタート" — so
    /// a list of complete spellings never keeps up.
    public static func isSpoken(in text: String) -> Bool {
        let normalised = normalise(text)
        guard !normalised.isEmpty else { return false }

        guard let lead = earliestRange(of: leads, in: normalised) else { return false }
        // The halves have to arrive in that order, or "start the link" counts.
        return normalised.range(of: tailPattern, options: .regularExpression, range: lead.upperBound ..< normalised.endIndex) != nil
    }

    private static let leads = ["リンク", "りんく", "link"]
    private static let tailPattern = "スタート|すたーと|start"

    private static func earliestRange(of needles: [String], in text: String) -> Range<String.Index>? {
        needles
            .compactMap { text.range(of: $0) }
            .min { $0.lowerBound < $1.lowerBound }
    }

    /// Lower-cased, with separators removed. Everything that carries sound stays,
    /// so the two halves survive whatever punctuation the recogniser inserts.
    private static func normalise(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .unicodeScalars
            .filter { !removedScalars.contains($0) }
            .map(String.init)
            .joined()
    }

    private static let removedScalars: Set<Unicode.Scalar> = [
        " ", "\u{3000}", ".", ",", "!", "?", "-", "–", "—",
        "、", "。", "！", "？", "・", "「", "」",
    ]
}
