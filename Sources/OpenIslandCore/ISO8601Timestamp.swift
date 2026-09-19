import Foundation

/// ISO 8601 timestamps as they actually arrive: mitama Browser writes
/// milliseconds (`…T09:00:00.000Z`), the Codex gate hook writes none
/// (`…T09:00:00Z`), and one `ISO8601DateFormatter` only ever accepts one of
/// the two shapes. One place that tries both, so a parser meeting the other
/// shape does not silently return nil.
///
/// A formatter is built per call rather than shared: `ISO8601DateFormatter`
/// is not `Sendable`, and these parses happen a handful of times a minute.
public enum ISO8601Timestamp {
    public static func parse(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }

        let whole = ISO8601DateFormatter()
        whole.formatOptions = [.withInternetDateTime]
        return whole.date(from: text)
    }
}
