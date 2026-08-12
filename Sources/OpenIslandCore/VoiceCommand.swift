import Foundation

public enum VoiceIntent: Equatable, Sendable {
    case approve
    case deny
    case chooseOption(index: Int)
    case unrecognised
}

public enum VoiceCommandParser: Sendable {
    /// `options` contains the labels on a question card. Approval cards have no options.
    public static func intent(from text: String, options: [String] = []) -> VoiceIntent {
        let normalisedText = normalise(text)
        guard !normalisedText.isEmpty else { return .unrecognised }

        let containsDenial = containsDenial(in: normalisedText)
        let containsApproval = containsApproval(in: normalisedText)

        // A correction such as "yes, no" must never turn into an approval.
        if containsDenial && containsApproval { return .unrecognised }
        if containsDenial { return .deny }
        if containsApproval { return .approve }

        guard !options.isEmpty else { return .unrecognised }

        if let number = Vocabulary.optionNumbers[normalisedText] {
            guard number <= options.count else { return .unrecognised }
            return .chooseOption(index: number - 1)
        }

        let normalisedOptions = options.map(normalise)
        if let exactMatch = normalisedOptions.firstIndex(of: normalisedText), !normalisedText.isEmpty {
            return .chooseOption(index: exactMatch)
        }

        // A shared fragment does not identify a choice well enough to act on it.
        let partialMatches = normalisedOptions.indices.filter { index in
            let option = normalisedOptions[index]
            return !option.isEmpty && (normalisedText.contains(option) || option.contains(normalisedText))
        }
        guard partialMatches.count == 1, let match = partialMatches.first else {
            return .unrecognised
        }
        return .chooseOption(index: match)
    }

    private static func containsApproval(in text: String) -> Bool {
        containsJapanesePhrase(in: text, phrases: Vocabulary.japaneseApprovals)
            || containsEnglishWord(in: text, words: Vocabulary.englishApprovals)
    }

    private static func containsDenial(in text: String) -> Bool {
        containsJapanesePhrase(in: text, phrases: Vocabulary.japaneseDenials)
            || containsEnglishWord(in: text, words: Vocabulary.englishDenials)
    }

    private static func containsJapanesePhrase(in text: String, phrases: Set<String>) -> Bool {
        phrases.contains { text.contains($0) }
    }

    private static func containsEnglishWord(in text: String, words: Set<String>) -> Bool {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains { words.contains(String($0)) }
    }

    private static func normalise(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .unicodeScalars
            .filter { !Vocabulary.removedPunctuation.contains($0) }
            .map(String.init)
            .joined()
    }

    private enum Vocabulary: Sendable {
        static let japaneseApprovals: Set<String> = ["はい", "許可", "承認", "いいよ", "オッケー", "オーケー"]
        static let englishApprovals: Set<String> = ["yes", "allow", "approve", "ok", "okay"]
        static let japaneseDenials: Set<String> = ["いいえ", "だめ", "ダメ", "拒否", "やめて"]
        static let englishDenials: Set<String> = ["no", "deny", "stop", "cancel"]

        static let optionNumbers: [String: Int] = [
            "1": 1, "1番": 1, "一": 1, "一番": 1, "いち": 1, "one": 1,
            "2": 2, "2番": 2, "二": 2, "二番": 2, "に": 2, "two": 2,
            "3": 3, "3番": 3, "三": 3, "三番": 3, "さん": 3, "three": 3,
            "4": 4, "4番": 4, "四": 4, "四番": 4, "よん": 4, "し": 4, "four": 4,
            "5": 5, "5番": 5, "五": 5, "五番": 5, "ご": 5, "five": 5,
            "6": 6, "6番": 6, "六": 6, "六番": 6, "ろく": 6, "six": 6,
            "7": 7, "7番": 7, "七": 7, "七番": 7, "なな": 7, "しち": 7, "seven": 7,
            "8": 8, "8番": 8, "八": 8, "八番": 8, "はち": 8, "eight": 8,
            "9": 9, "9番": 9, "九": 9, "九番": 9, "きゅう": 9, "く": 9, "nine": 9,
        ]

        static let removedPunctuation = CharacterSet.punctuationCharacters
            .union(CharacterSet(charactersIn: "。、"))
    }
}
