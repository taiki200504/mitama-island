import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Clipboard ledger")
struct ClipboardLedgerTests {
    private func item(
        _ text: String = "hello",
        hash: String? = nil,
        copiedAt: Date = Date(timeIntervalSince1970: 1000)
    ) -> ClipboardItem {
        .init(kind: .text(text), sourceBundleID: nil, copiedAt: copiedAt, contentHash: hash ?? text)
    }

    @Test("Inserting into an empty ledger just adds the item")
    func insertingIntoEmptyLedger() {
        let result = ClipboardLedger.inserting(item("a"), into: [])
        #expect(result.map(\.contentHash) == ["a"])
    }

    @Test("A new item always lands on top")
    func newItemLandsOnTop() {
        let existing = [item("old", hash: "old")]
        let result = ClipboardLedger.inserting(item("new", hash: "new"), into: existing)
        #expect(result.map(\.contentHash) == ["new", "old"])
    }

    @Test("Copying the same content again moves it back to the top instead of duplicating it")
    func duplicateContentMovesToTop() {
        let existing = [
            item("b", hash: "b"),
            item("a", hash: "a"),
        ]
        let result = ClipboardLedger.inserting(item("a", hash: "a"), into: existing)
        #expect(result.map(\.contentHash) == ["a", "b"])
        #expect(result.count == 2)
    }

    @Test("The ledger never grows past its item cap")
    func capsAtMaximumCount() {
        let existing = (0..<ClipboardLedger.maximumCount).map { item("i\($0)", hash: "h\($0)") }
        let result = ClipboardLedger.inserting(item("new", hash: "new"), into: existing)
        #expect(result.count == ClipboardLedger.maximumCount)
        #expect(result.first?.contentHash == "new")
        // The oldest one fell off the end to make room.
        #expect(!result.contains { $0.contentHash == "h\(ClipboardLedger.maximumCount - 1)" })
    }

    @Test("An older item that no longer fits alongside a new one is dropped, even below the count cap")
    func capsAtMaximumBytes() {
        let bigText = String(repeating: "x", count: Int(ClipboardLedger.maximumTotalBytes) - 10)
        let existing = [item(bigText, hash: "big")]
        let result = ClipboardLedger.inserting(item("small", hash: "small"), into: existing)
        #expect(result.map(\.contentHash) == ["small"])
    }

    @Test("A single new item survives even if it alone is over the byte cap")
    func oversizedSoleItemStillSurvives() {
        let hugeText = String(repeating: "x", count: Int(ClipboardLedger.maximumTotalBytes) + 100)
        let result = ClipboardLedger.inserting(item(hugeText, hash: "huge"), into: [])
        #expect(result.map(\.contentHash) == ["huge"])
    }

    @Test("Removing drops only the matching id")
    func removingDropsOnlyMatchingID() {
        let a = item("a", hash: "a")
        let b = item("b", hash: "b")
        let result = ClipboardLedger.removing(id: a.id, from: [a, b])
        #expect(result.map(\.contentHash) == ["b"])
    }

    @Test("Removing an id that isn't there is a no-op")
    func removingUnknownIDIsNoOp() {
        let a = item("a", hash: "a")
        let result = ClipboardLedger.removing(id: UUID(), from: [a])
        #expect(result.map(\.contentHash) == ["a"])
    }
}
