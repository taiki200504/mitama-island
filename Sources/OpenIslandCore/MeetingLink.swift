import Foundation

/// Finds a video-call link buried in a calendar entry's location, notes, or
/// URL field.
///
/// Calendar invites rarely put the link on its own line — it's usually
/// wrapped in "Join Zoom Meeting: <url>" or sitting in a paragraph of dial-in
/// numbers. This looks for the handful of hosts that matter rather than
/// trying to be a general URL extractor.
public enum MeetingLink {
    /// The regex below is intentionally permissive about what follows the
    /// host — a calendar invite's URL is usually followed by whitespace,
    /// punctuation, or nothing at all, and `URL(string:)` is what actually
    /// validates the result.
    private static let pattern = try! NSRegularExpression(
        pattern: #"https?://[^\s<>"']*(?:zoom\.us|meet\.google\.com|teams\.microsoft\.com|webex\.com)[^\s<>"']*"#,
        options: [.caseInsensitive]
    )

    /// The first valid meeting link found across `texts`, in order. `nil`
    /// entries (a calendar entry with no notes, say) are skipped rather than
    /// treated as a search failure.
    public static func find(in texts: [String?]) -> URL? {
        for text in texts {
            guard let text else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = pattern.firstMatch(in: text, range: range),
                  let matchRange = Range(match.range, in: text)
            else { continue }
            if let url = URL(string: String(text[matchRange])), url.host != nil {
                return url
            }
        }
        return nil
    }
}
