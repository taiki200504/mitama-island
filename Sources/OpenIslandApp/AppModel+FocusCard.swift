import Foundation
import OpenIslandCore
import os

/// Focus Card state management extension for AppModel.
extension AppModel {
    private static let focusCardLogger = Logger(subsystem: "com.mitama.island", category: "focus-card")

    /// Save the current work state as a Resume Card.
    ///
    /// Called when the user presses the Focus Card interrupt shortcut.
    /// Saves the currently active session title as the Resume Card title,
    /// and optionally accepts a one-line next action and shelf reference.
    @MainActor
    func saveInterruptionCard(
        title: String? = nil,
        nextAction: String = "",
        shelfReference: String? = nil
    ) async {
        // Use active session title if no title provided
        let cardTitle = title ?? state.activeActionableSession?.title ?? "Unnamed Work"

        let card = ResumeCard(
            title: cardTitle,
            nextAction: nextAction,
            shelfReference: shelfReference
        )

        do {
            try await focusCardStore.save(card)
            await refreshFocusCard()
            Self.focusCardLogger.debug("Saved Resume Card: \(cardTitle)")
        } catch {
            Self.focusCardLogger.error("Failed to save Resume Card: \(error, privacy: .public)")
        }
    }

    /// Resume from a saved Resume Card.
    ///
    /// Makes the card active and optionally jumps back to its associated context.
    @MainActor
    func resumeFromCard(_ card: ResumeCard) async {
        do {
            try await focusCardStore.resume(card)
            await refreshFocusCard()
            Self.focusCardLogger.debug("Resumed from card: \(card.title)")
            // In future phases, implement jump-back and context restoration
        } catch {
            Self.focusCardLogger.error("Failed to resume from card: \(error, privacy: .public)")
        }
    }

    /// Dismiss the current Resume Card without resuming.
    @MainActor
    func dismissCurrentCard() async {
        do {
            try await focusCardStore.dismissCurrent()
            await refreshFocusCard()
            Self.focusCardLogger.debug("Dismissed current Resume Card")
        } catch {
            Self.focusCardLogger.error("Failed to dismiss Resume Card: \(error, privacy: .public)")
        }
    }

    /// Copies the store's contents into `focusCard`, which is what the island
    /// actually draws from.
    ///
    /// The store is an actor and the island draws on the main thread, so the
    /// view can never await it. Every operation that changes the store ends
    /// here; nothing else is allowed to write `focusCard`.
    @MainActor
    func refreshFocusCard() async {
        do {
            focusCard = FocusCardState(
                currentCard: try await focusCardStore.current(),
                history: try await focusCardStore.history()
            )
        } catch {
            Self.focusCardLogger.error("Failed to read Resume Cards: \(error, privacy: .public)")
        }
    }

    /// Get the current active Resume Card, if one exists.
    @MainActor
    func currentResumeCard() async -> ResumeCard? {
        do {
            return try await focusCardStore.current()
        } catch {
            Self.focusCardLogger.error("Failed to get current Resume Card: \(error, privacy: .public)")
            return nil
        }
    }

    /// Get the history of recent Resume Cards.
    @MainActor
    func resumeCardHistory() async -> [ResumeCard] {
        do {
            return try await focusCardStore.history()
        } catch {
            Self.focusCardLogger.error("Failed to get Resume Card history: \(error, privacy: .public)")
            return []
        }
    }

    /// Prune old Resume Cards older than 7 days.
    @MainActor
    func pruneOldResumeCards() async {
        do {
            try await focusCardStore.pruneOldCards()
            await refreshFocusCard()
            Self.focusCardLogger.debug("Pruned old Resume Cards")
        } catch {
            Self.focusCardLogger.error("Failed to prune old Resume Cards: \(error, privacy: .public)")
        }
    }
}
