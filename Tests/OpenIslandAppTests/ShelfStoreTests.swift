import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

/// `ShelfStore` over a scratch directory, so persistence and expiry can be
/// checked without touching the real `Application Support` folder.
@MainActor
struct ShelfStoreTests {
    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ShelfStoreTests-\(UUID().uuidString)")
    }

    private func makeSourceFile(named name: String, in directory: URL, contents: Data = Data([0x01, 0x02])) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url)
        return url
    }

    @Test("What one instance saves, a later instance over the same directory reloads")
    func roundTripsAcrossInstances() throws {
        let directory = makeTempDirectory()
        let sourceDirectory = makeTempDirectory()
        let fileURL = try makeSourceFile(named: "notes.md", in: sourceDirectory)

        let first = ShelfStore(directory: directory)
        first.load()
        first.accept([fileURL])
        #expect(first.items.count == 1)

        let second = ShelfStore(directory: directory)
        second.load()
        #expect(second.items.map(\.displayName) == ["notes.md"])
        #expect(FileManager.default.fileExists(atPath: second.fileURL(for: second.items[0]).path))
    }

    @Test("A ledger entry whose file is gone does not survive a reload")
    func loadDropsEntriesWhoseFileIsMissing() throws {
        let directory = makeTempDirectory()
        let sourceDirectory = makeTempDirectory()
        let fileURL = try makeSourceFile(named: "notes.md", in: sourceDirectory)

        let first = ShelfStore(directory: directory)
        first.load()
        first.accept([fileURL])
        try FileManager.default.removeItem(at: first.fileURL(for: first.items[0]))

        let second = ShelfStore(directory: directory)
        second.load()
        #expect(second.items.isEmpty)
    }

    @Test("Pruning removes only what has passed the configured ttl")
    func pruneExpiredRemovesOnlyStaleItems() throws {
        let directory = makeTempDirectory()
        let sourceDirectory = makeTempDirectory()
        let oldFile = try makeSourceFile(named: "old.md", in: sourceDirectory)
        let recentFile = try makeSourceFile(named: "recent.md", in: sourceDirectory, contents: Data([0x03]))

        let store = ShelfStore(directory: directory)
        store.load()
        let baseline = Date(timeIntervalSince1970: 1_000_000)
        store.expiryProvider = { 3600 }

        store.accept([oldFile])
        store.accept([recentFile])
        #expect(store.items.count == 2)

        // Pretend the first item is over an hour old and the second is not.
        let aged = store.items.map { item -> ShelfItem in
            item.displayName == "old.md"
                ? ShelfItem(
                    id: item.id,
                    displayName: item.displayName,
                    storedName: item.storedName,
                    byteSize: item.byteSize,
                    addedAt: baseline.addingTimeInterval(-7200)
                )
                : ShelfItem(
                    id: item.id,
                    displayName: item.displayName,
                    storedName: item.storedName,
                    byteSize: item.byteSize,
                    addedAt: baseline
                )
        }
        store.loadFixture(aged)

        let removed = store.pruneExpired(now: baseline)
        #expect(removed.map(\.displayName) == ["old.md"])
        #expect(store.items.map(\.displayName) == ["recent.md"])
    }

    @Test("A never-expiring shelf prunes nothing")
    func pruneExpiredIsANoOpWhenTTLIsNil() throws {
        let directory = makeTempDirectory()
        let sourceDirectory = makeTempDirectory()
        let fileURL = try makeSourceFile(named: "notes.md", in: sourceDirectory)

        let store = ShelfStore(directory: directory)
        store.load()
        store.accept([fileURL])
        // expiryProvider defaults to `{ nil }`.
        #expect(store.pruneExpired(now: Date(timeIntervalSince1970: 4_000_000_000)).isEmpty)
        #expect(store.items.count == 1)
    }
}
