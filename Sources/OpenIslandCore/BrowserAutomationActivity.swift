import Foundation

/// The current automation activity from mitama Browser.
///
/// mitama Browser writes this file on every navigation of a tab the human is not
/// looking at, providing context about what automation is driving.
public struct BrowserAutomationActivity: Equatable, Sendable, Codable {
    /// The mitama account ID (e.g., "gugen")
    public let accountId: String
    /// Human-readable account label (e.g., "Gugen")
    public let accountLabel: String
    /// Page title of the tab being automated
    public let title: String
    /// Full URL of the page
    public let url: URL?
    /// ISO8601 timestamp of the navigation
    public let at: Date

    public init(accountId: String, accountLabel: String, title: String, url: URL?, at: Date) {
        self.accountId = accountId
        self.accountLabel = accountLabel
        self.title = title
        self.url = url
        self.at = at
    }

    enum CodingKeys: String, CodingKey {
        case accountId, accountLabel, title, url, at
    }

    /// Parses automation activity from the mitama Browser activity file.
    ///
    /// Treats anything older than `freshness` seconds as stale. The file may be
    /// missing, corrupt, or unparsable — returns `nil` in all error cases.
    ///
    /// - Parameters:
    ///   - data: Raw JSON data from `~/Library/Application Support/mitama Browser/automation-activity.json`
    ///   - now: Reference date for freshness calculation
    ///   - freshness: Maximum age in seconds (default 10 minutes)
    /// - Returns: Parsed activity if fresh and valid, `nil` otherwise
    public static func parse(_ data: Data, now: Date, freshness: TimeInterval = 10 * 60) -> BrowserAutomationActivity? {
        let decoder = JSONDecoder()
        // mitama Browser writes `new Date().toISOString()` — ISO 8601 **with**
        // milliseconds, which `.iso8601` alone rejects, and which the default
        // (a number of seconds) never even looks at.
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = ISO8601Timestamp.parse(text) else {
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "Not an ISO 8601 timestamp: \(text)"
                )
            }
            return date
        }
        guard let activity = try? decoder.decode(BrowserAutomationActivity.self, from: data) else {
            return nil
        }

        let age = now.timeIntervalSince(activity.at)
        guard age >= 0, age <= freshness else {
            return nil
        }

        return activity
    }
}
