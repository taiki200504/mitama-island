import Foundation

/// A short sentence the island shows the user and then forgets.
///
/// Exists because the camera and the microphone both fail in ways only they can
/// explain — permission refused, nothing heard, words that made no sense. Those
/// explanations were being written to a log nobody reads. This is the value the
/// island puts on screen instead.
public struct IslandNotice: Equatable, Sendable, Identifiable {
    /// Changes on every new notice, so the view animates a replacement rather
    /// than mutating text under the reader's eyes.
    public let id: UUID
    public let text: String
    public let shownAt: Date

    public init(id: UUID = UUID(), text: String, shownAt: Date) {
        self.id = id
        self.text = text
        self.shownAt = shownAt
    }

    /// How long a notice stays up.
    ///
    /// Long enough to read a sentence about why nothing happened, short enough
    /// that it is gone before it becomes part of the furniture.
    public static let lifetime: TimeInterval = 4.0

    public func hasExpired(at moment: Date) -> Bool {
        moment.timeIntervalSince(shownAt) >= Self.lifetime
    }

    public func remainingTime(at moment: Date) -> TimeInterval {
        max(0, Self.lifetime - moment.timeIntervalSince(shownAt))
    }
}

/// Decides what the island should be showing, given what arrived and when.
///
/// Pulled out of the view so the rules — a later notice wins, blank text says
/// nothing, an old notice goes away on its own — can be checked without a
/// screen.
public enum IslandNoticeQueue: Sendable {
    /// Returns the notice to display, or nil to show none.
    ///
    /// A new arrival always replaces what is up. Two explanations stacked on top
    /// of each other are worse than the most recent one alone: by the time the
    /// second arrives, the first is describing a moment that has passed.
    public static func accept(
        _ text: String,
        over current: IslandNotice?,
        at moment: Date,
        id: UUID = UUID()
    ) -> IslandNotice? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // An empty status is how the sessions say "nothing to report". It must
        // not push a blank bar onto the screen.
        guard !trimmed.isEmpty else { return current }
        return IslandNotice(id: id, text: trimmed, shownAt: moment)
    }

    /// Returns the notice that should still be on screen at this moment.
    public static func settle(_ current: IslandNotice?, at moment: Date) -> IslandNotice? {
        guard let current, !current.hasExpired(at: moment) else { return nil }
        return current
    }
}
