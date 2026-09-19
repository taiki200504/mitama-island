import Foundation

/// A saved interruption point that can be resumed later.
///
/// When the user presses the "中断" (pause/interrupt) shortcut while working,
/// a Resume Card is created with:
/// - title: what they were working on
/// - note: optional one-line hint for next action
/// - context: optional reference to a shelf item (file path, URL, etc.)
/// - savedAt: when the card was created
/// - lastShownAt: tracks when user last viewed the card
///
/// On resume, the card shows the minimal next action without summarizing the
/// full session. Nothing is sent to any AI service; all storage is local.
public struct ResumeCard: Equatable, Codable, Sendable {
    /// Unique identifier for this card.
    public let id: String

    /// What the user was working on (e.g., "Implement Focus Card feature").
    /// Defaults to the current agent session title if not provided.
    public var title: String

    /// Optional one-line hint for the next action.
    /// Empty string means no note was provided.
    public var nextAction: String

    /// Optional reference to a shelf item (file path, URL, or clipboard item ID).
    /// Helps user jump back to the context they were in.
    public var shelfReference: String?

    /// When this card was created.
    public let savedAt: Date

    /// When the user last viewed this card (for sorting/prioritization).
    public var lastShownAt: Date

    public init(
        id: String = UUID().uuidString,
        title: String,
        nextAction: String = "",
        shelfReference: String? = nil,
        savedAt: Date = .now,
        lastShownAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.nextAction = nextAction
        self.shelfReference = shelfReference
        self.savedAt = savedAt
        self.lastShownAt = lastShownAt
    }

    /// Returns a minimal display string suitable for the closed island.
    /// Shows title and next action, omitting the shelf reference.
    public func displayLabel() -> String {
        if nextAction.isEmpty {
            return title
        }
        return "\(title) — \(nextAction)"
    }
}

/// The Focus Card is the island's state representation of a saved interruption.
///
/// Unlike a session, which represents an ongoing agent run, the Focus Card
/// is a lightweight marker that says "the user paused here and wants to get
/// back to work quickly." It lives alongside sessions but has its own lifecycle.
public struct FocusCardState: Equatable, Sendable {
    /// The current active Resume Card, if one exists.
    /// `nil` means no interruption has been saved.
    public var currentCard: ResumeCard?

    /// All saved Resume Cards, sorted by lastShownAt (most recent first).
    /// Cards are kept for 7 days or until the user dismisses them.
    /// Defaults to empty array if no cards have been saved.
    public var history: [ResumeCard]

    public init(currentCard: ResumeCard? = nil, history: [ResumeCard] = []) {
        self.currentCard = currentCard
        self.history = history
    }

    /// Saves a new Resume Card as the current card.
    /// Adds the old current card to history if it exists.
    public mutating func save(_ card: ResumeCard) {
        if let current = currentCard {
            history.insert(current, at: 0)
        }
        currentCard = card
    }

    /// Resumes from a card in history, making it the current card.
    public mutating func resume(_ card: ResumeCard) {
        currentCard = card
        history.removeAll { $0.id == card.id }
    }

    /// Dismisses the current card without resuming.
    public mutating func dismissCurrent() {
        if let current = currentCard {
            // Move to history for a short time before auto-archiving
            history.insert(current, at: 0)
        }
        currentCard = nil
    }

    /// Removes cards older than the given interval.
    /// Only removes cards that are not currently active.
    public mutating func pruneOldCards(olderThan interval: TimeInterval, now: Date = .now) {
        let cutoff = now.addingTimeInterval(-interval)
        history.removeAll { $0.savedAt < cutoff }
    }
}
