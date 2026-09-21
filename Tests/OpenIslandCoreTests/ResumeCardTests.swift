import Foundation
import Testing

@testable import OpenIslandCore

@Suite("ResumeCard")
struct ResumeCardTests {
    @Test("ResumeCard initializes with default values")
    func defaultInitialization() {
        let card = ResumeCard(
            title: "Implement Focus Card",
            nextAction: "Add keyboard shortcut handling"
        )

        #expect(card.title == "Implement Focus Card")
        #expect(card.nextAction == "Add keyboard shortcut handling")
        #expect(card.shelfReference == nil)
        #expect(card.savedAt <= Date.now)
    }

    @Test("ResumeCard.displayLabel combines title and nextAction")
    func displayLabel() {
        let card1 = ResumeCard(title: "Task", nextAction: "Do it")
        #expect(card1.displayLabel() == "Task — Do it")

        let card2 = ResumeCard(title: "Task", nextAction: "")
        #expect(card2.displayLabel() == "Task")
    }

    @Test("ResumeCard encodes and decodes as JSON")
    func codable() throws {
        let card = ResumeCard(
            id: "test-123",
            title: "Test task",
            nextAction: "Test action",
            shelfReference: "/path/to/file"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = try encoder.encode(card)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ResumeCard.self, from: json)

        #expect(decoded.id == card.id)
        #expect(decoded.title == card.title)
        #expect(decoded.nextAction == card.nextAction)
        #expect(decoded.shelfReference == card.shelfReference)
    }
}

@Suite("FocusCardState")
struct FocusCardStateTests {
    @Test("FocusCardState initializes empty")
    func defaultInitialization() {
        let state = FocusCardState()

        #expect(state.currentCard == nil)
        #expect(state.history.isEmpty)
    }

    @Test("save() moves current card to history and sets new current")
    func saveCard() {
        var state = FocusCardState()

        let card1 = ResumeCard(title: "First task")
        state.save(card1)
        #expect(state.currentCard?.id == card1.id)
        #expect(state.history.isEmpty)

        let card2 = ResumeCard(title: "Second task")
        state.save(card2)
        #expect(state.currentCard?.id == card2.id)
        #expect(state.history.count == 1)
        #expect(state.history[0].id == card1.id)
    }

    @Test("resume() moves card from history to current")
    func resumeCard() {
        var state = FocusCardState()

        let card1 = ResumeCard(title: "First")
        let card2 = ResumeCard(title: "Second")
        state.save(card1)
        state.save(card2)

        state.resume(card1)
        #expect(state.currentCard?.id == card1.id)
        #expect(state.history.count == 1)
        #expect(state.history[0].id == card2.id)
    }

    @Test("dismissCurrent() clears current and moves to history")
    func dismissCurrent() {
        var state = FocusCardState()
        let card = ResumeCard(title: "Task")
        state.save(card)

        state.dismissCurrent()
        #expect(state.currentCard == nil)
        #expect(state.history.count == 1)
        #expect(state.history[0].id == card.id)
    }

    @Test("pruneOldCards() removes cards older than interval")
    func pruneOldCards() {
        var state = FocusCardState()

        let now = Date.now
        let oldDate = now.addingTimeInterval(-8 * 24 * 3600) // 8 days ago
        let recentDate = now.addingTimeInterval(-2 * 24 * 3600) // 2 days ago

        let oldCard = ResumeCard(
            title: "Old task",
            savedAt: oldDate,
            lastShownAt: oldDate
        )
        let recentCard = ResumeCard(
            title: "Recent task",
            savedAt: recentDate,
            lastShownAt: recentDate
        )

        state.history = [oldCard, recentCard]

        // Prune cards older than 7 days
        state.pruneOldCards(olderThan: 7 * 24 * 3600, now: now)

        #expect(state.history.count == 1)
        #expect(state.history[0].id == recentCard.id)
    }
}
