import Foundation

/// Finds a video-call link buried in a calendar entry's location, notes, or
/// URL field.
///
/// Calendar invites rarely put the link on its own line — it's usually
/// wrapped in "Join Zoom Meeting: <url>" or sitting in a paragraph of dial-in
/// numbers. This looks for the handful of hosts that matter rather than
/// trying to be a general URL extractor.
public enum MeetingLink {
    /// Video-call hosts this trusts, plus any of their subdomains —
    /// `https://us02web.zoom.us/j/…` counts as `zoom.us` the same way
    /// `https://zoom.us/j/…` does.
    private static let trustedHosts: Set<String> = [
        "zoom.us",
        "meet.google.com",
        "teams.microsoft.com",
        "teams.live.com",
        "webex.com",
    ]

    /// A coarse pre-filter only — permissive about what follows the host,
    /// since a calendar invite's URL is usually followed by whitespace,
    /// punctuation, or nothing at all. It is not what decides trust: a
    /// crafted `https://evil.com/path/zoom.us/…` matches this regex too,
    /// which is exactly why `isTrusted` below checks the URL's actual host
    /// rather than trusting the substring the regex happened to find.
    private static let pattern = try! NSRegularExpression(
        pattern: #"https?://[^\s<>"']*(?:zoom\.us|meet\.google\.com|teams\.microsoft\.com|teams\.live\.com|webex\.com)[^\s<>"']*"#,
        options: [.caseInsensitive]
    )

    /// Trailing characters a sentence tends to leave stuck to a URL —
    /// "join here: https://zoom.us/j/123." should not carry the period.
    private static let trailingPunctuation = CharacterSet(charactersIn: ".,;)>\"'")

    /// The first valid, trusted meeting link found across `texts`, in order.
    /// `nil` entries (a calendar entry with no notes, say) are skipped
    /// rather than treated as a search failure.
    public static func find(in texts: [String?]) -> URL? {
        for text in texts {
            guard let text else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = pattern.firstMatch(in: text, range: range),
                  let matchRange = Range(match.range, in: text)
            else { continue }
            let candidate = String(text[matchRange]).trimmingCharacters(in: trailingPunctuation)
            if let url = URL(string: candidate), isTrusted(url) {
                return url
            }
        }
        return nil
    }

    /// `https` only, and the host has to *be* one of `trustedHosts` or a
    /// subdomain of one. Guards against a link whose regex-matched text
    /// contains a trusted name without that name actually being the host —
    /// `https://evil.com/x/zoom.us/…` has `evil.com` as its host, not
    /// `zoom.us`, no matter what its path says.
    private static func isTrusted(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return trustedHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
    }
}
