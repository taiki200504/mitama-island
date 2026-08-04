import Foundation

/// Derives a short name for a session from the first thing the user asked it.
///
/// Three sessions open in the same repository all show the same workspace name,
/// which is exactly when you need to tell them apart. The first prompt is what
/// distinguishes them.
///
/// Deliberately no language model: this runs on every session on every update,
/// the answer has to be the same every time, and "shorten a sentence" does not
/// need judgement.
public enum SessionAutoName {
    /// Long enough to stay meaningful, short enough for a single row.
    public static let maximumLength = 42

    /// Openers that carry no information about what the session is for.
    /// Matched case-insensitively at the very start only, so "Can you see the
    /// fix in canvas.ts" keeps its subject.
    private static let filler = [
        "please ", "could you ", "can you ", "i want you to ", "i'd like you to ",
        "let's ", "lets ", "help me ", "i need you to ", "would you "
    ]

    /// Returns a name, or `nil` when the prompt carries nothing worth showing —
    /// the caller then keeps the workspace name rather than displaying a blank.
    public static func derive(from prompt: String?) -> String? {
        guard let prompt else { return nil }

        // A pasted stack trace or file dump: the first line is the only part
        // that reads as a request, and the rest would be noise.
        var text = prompt
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return nil }

        let hadFiller = text != stripFiller(from: text)
        // A prompt that is nothing but an opener has no subject to show.
        if filler.contains(where: { $0.trimmingCharacters(in: .whitespaces) == text.lowercased() }) {
            return nil
        }
        text = stripFiller(from: text)
        // "please fix the login" would otherwise become a lower-case name in a
        // list where every other row starts with a capital.
        if hadFiller { text = capitalisingFirstLetter(text) }
        text = firstClause(of: text)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " \t.,:;-–—"))

        guard !text.isEmpty else { return nil }
        return truncate(text)
    }

    private static func stripFiller(from text: String) -> String {
        var result = text
        // Repeat: "could you please add …" has two.
        var changed = true
        while changed {
            changed = false
            for opener in filler where result.lowercased().hasPrefix(opener) {
                result = String(result.dropFirst(opener.count))
                changed = true
                break
            }
        }
        return result
    }

    /// Everything up to the first sentence break, so a two-sentence prompt does
    /// not become a name that trails off mid-thought.
    private static func firstClause(of text: String) -> String {
        let characters = Array(text)
        // Japanese terminators as well: this app's own user writes prompts in
        // it, and they need no following space.
        let alwaysBreaks: Set<Character> = ["?", "!", "。", "？", "！"]

        for (index, character) in characters.enumerated() {
            let breaks: Bool
            if alwaysBreaks.contains(character) {
                breaks = true
            } else if character == "." {
                // A dot inside `canvas.ts` or `v1.2` is not a sentence end.
                // Only one followed by a space or the end of the line is.
                let next = index + 1 < characters.count ? characters[index + 1] : " "
                breaks = next.isWhitespace
            } else {
                breaks = false
            }

            // A break in the first few characters is punctuation, not a
            // sentence — "e.g. rewrite the parser" must keep its subject.
            guard breaks, index >= 8 else { continue }
            return String(characters[0..<index])
        }
        return text
    }

    private static func capitalisingFirstLetter(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased() + text.dropFirst()
    }

    /// Cuts at a word boundary where there is one, so a name never ends
    /// mid-word. Languages without spaces fall back to a hard cut.
    private static func truncate(_ text: String) -> String {
        guard text.count > maximumLength else { return text }
        let clipped = String(text.prefix(maximumLength))
        if let lastSpace = clipped.lastIndex(of: " "), clipped.distance(from: clipped.startIndex, to: lastSpace) > maximumLength / 2 {
            return String(clipped[clipped.startIndex..<lastSpace]) + "…"
        }
        return clipped + "…"
    }
}
