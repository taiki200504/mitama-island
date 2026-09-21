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

/// 固定した棚の項目。守っているのは「固定したのに消える」を起こさないこと。
struct ShelfPinTests {
    private let now = Date(timeIntervalSince1970: 1_758_000_000)

    private func item(_ name: String, addedAgo: TimeInterval, pinnedAgo: TimeInterval? = nil) -> ShelfItem {
        ShelfItem(
            displayName: name,
            storedName: name,
            byteSize: 10,
            addedAt: now.addingTimeInterval(-addedAgo),
            pinnedAt: pinnedAgo.map { now.addingTimeInterval(-$0) }
        )
    }

    @Test
    func pinnedItemsFloatAboveNewerOnes() {
        let ordered = ShelfLedger.ordered([
            item("新しい", addedAgo: 10),
            item("古いが固定", addedAgo: 9_000, pinnedAgo: 100),
            item("中くらい", addedAgo: 100),
        ])

        #expect(ordered.map(\.displayName) == ["古いが固定", "新しい", "中くらい"])
    }

    /// 置いたままにしておくために固定したのに、時間で消えるなら意味がない。
    @Test
    func aPinnedItemNeverExpires() {
        let stale = item("放置", addedAgo: 9_000)
        let pinned = item("固定", addedAgo: 9_000, pinnedAgo: 10)

        let expired = ShelfLedger.expired([stale, pinned], now: now, ttl: 3_600)
        #expect(expired.map(\.displayName) == ["放置"])
    }

    /// 固定した欄を足す前に保存された棚も、そのまま読み直せること。
    /// ここが崩れると、棚が丸ごと空になって見える。
    @Test
    func aShelfSavedBeforePinningStillDecodes() throws {
        let legacy = """
        [{"id":"8B8E3B6E-3D3E-4E2E-9B1E-2C7B4F5A6D7E","displayName":"notes.md",\
        "storedName":"notes.md","byteSize":12,"addedAt":0}]
        """

        let decoded = try JSONDecoder().decode([ShelfItem].self, from: Data(legacy.utf8))
        #expect(decoded.count == 1)
        #expect(decoded.first?.isPinned == false)
    }
}
