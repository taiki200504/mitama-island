import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Shelf ledger")
struct ShelfTests {
    private func item(
        _ name: String = "notes.md",
        bytes: Int64 = 1024,
        addedAt: Date = Date(timeIntervalSince1970: 1000)
    ) -> ShelfItem {
        .init(displayName: name, storedName: name, byteSize: bytes, addedAt: addedAt)
    }

    @Test("An empty shelf takes anything reasonable")
    func emptyShelfAccepts() {
        #expect(ShelfLedger.refusal(adding: 1024, to: []) == nil)
    }

    @Test("One enormous file is refused on its own")
    func oversizedItemIsRefused() {
        let huge = ShelfLedger.maximumItemBytes + 1
        #expect(ShelfLedger.refusal(adding: huge, to: []) == .tooLarge(byteSize: huge))
    }

    @Test("A full shelf refuses, and says how much it is holding")
    func fullShelfRefuses() {
        let big = item(bytes: ShelfLedger.maximumTotalBytes - 100)
        let refusal = ShelfLedger.refusal(adding: 500, to: [big])
        #expect(refusal == .full(usedBytes: big.byteSize))
    }

    @Test("Too many items is its own refusal")
    func tooManyItemsRefuses() {
        let many = (0 ..< ShelfLedger.maximumCount).map { item("f\($0)", bytes: 1) }
        #expect(ShelfLedger.refusal(adding: 1, to: many) == .tooMany(count: many.count))
    }

    @Test("Each refusal has its own sentence")
    func refusalsHaveDistinctKeys() {
        let all: [ShelfLedger.Refusal] = [.full(usedBytes: 0), .tooMany(count: 0), .tooLarge(byteSize: 0)]
        #expect(Set(all.map(\.noticeKey)).count == all.count)
    }

    /// Two files called notes.md must both survive.
    @Test("A taken name gets a number before the extension")
    func uniqueNameNumbersBeforeExtension() {
        #expect(ShelfLedger.uniqueStoredName(for: "notes.md", taken: []) == "notes.md")
        #expect(ShelfLedger.uniqueStoredName(for: "notes.md", taken: ["notes.md"]) == "notes 2.md")
        #expect(
            ShelfLedger.uniqueStoredName(for: "notes.md", taken: ["notes.md", "notes 2.md"]) == "notes 3.md"
        )
    }

    /// The number must not land after the extension, or the file stops opening
    /// in the app it belongs to.
    @Test("A name with no extension still gets numbered")
    func uniqueNameWithoutExtension() {
        #expect(ShelfLedger.uniqueStoredName(for: "README", taken: ["README"]) == "README 2")
    }

    @Test("Dotted names keep only the real extension")
    func uniqueNameWithDots() {
        let result = ShelfLedger.uniqueStoredName(for: "archive.tar.gz", taken: ["archive.tar.gz"])
        #expect(result == "archive.tar 2.gz")
    }

    @Test("Total size adds up")
    func totalBytesSums() {
        #expect(ShelfLedger.totalBytes([item(bytes: 100), item(bytes: 250)]) == 350)
        #expect(ShelfLedger.totalBytes([]) == 0)
    }

    /// What you just put down is what you are about to pick up.
    @Test("Newest is first")
    func orderedNewestFirst() {
        let old = item("old", addedAt: Date(timeIntervalSince1970: 100))
        let new = item("new", addedAt: Date(timeIntervalSince1970: 900))
        #expect(ShelfLedger.ordered([old, new]).first?.displayName == "new")
    }

    // MARK: Expiry

    @Test("Nil ttl never expires anything, no matter how old")
    func nilTTLNeverExpires() {
        let ancient = item(addedAt: Date(timeIntervalSince1970: 0))
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(ShelfLedger.expired([ancient], now: now, ttl: nil).isEmpty)
    }

    @Test("An item younger than the ttl survives")
    func youngerThanTTLSurvives() {
        let added = Date(timeIntervalSince1970: 1000)
        let fresh = item(addedAt: added)
        let now = added.addingTimeInterval(59)
        #expect(ShelfLedger.expired([fresh], now: now, ttl: 60).isEmpty)
    }

    @Test("An item exactly at the ttl boundary is expired")
    func exactlyAtTTLBoundaryExpires() {
        let added = Date(timeIntervalSince1970: 1000)
        let borderline = item(addedAt: added)
        let now = added.addingTimeInterval(60)
        #expect(ShelfLedger.expired([borderline], now: now, ttl: 60) == [borderline])
    }

    @Test("An item past the ttl is expired, one younger is not")
    func mixedExpiryFiltersOnlyThePastDue() {
        let added = Date(timeIntervalSince1970: 1000)
        let old = item("old", addedAt: added)
        let recent = item("recent", addedAt: added.addingTimeInterval(50))
        let now = added.addingTimeInterval(61)
        #expect(ShelfLedger.expired([old, recent], now: now, ttl: 60) == [old])
    }
}
