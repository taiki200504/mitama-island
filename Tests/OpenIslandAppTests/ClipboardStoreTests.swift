import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

/// `ClipboardStore` over a scratch directory, so persistence can be checked
/// without touching the real `Application Support` folder.
@MainActor
struct ClipboardStoreTests {
    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardStoreTests-\(UUID().uuidString)")
    }

    private func textItem(_ text: String, hash: String) -> ClipboardItem {
        .init(kind: .text(text), sourceBundleID: nil, copiedAt: .now, contentHash: hash)
    }

    private func imageItem(hash: String) -> ClipboardItem {
        .init(
            kind: .image(pngData: Data([0x01, 0x02, 0x03]), thumbnail: Data([0x04])),
            sourceBundleID: nil,
            copiedAt: .now,
            contentHash: hash
        )
    }

    @Test("With persistence off, nothing survives a fresh instance over the same directory")
    func recordingWithoutPersistenceDoesNotSurvive() {
        let directory = makeTempDirectory()

        let first = ClipboardStore(directory: directory)
        first.persistsToDisk = { false }
        first.load()
        first.record(textItem("hello", hash: "a"))
        #expect(first.items.count == 1)

        let second = ClipboardStore(directory: directory)
        second.persistsToDisk = { false }
        second.load()
        #expect(second.items.isEmpty)
    }

    @Test("With persistence on, a text item survives a fresh instance over the same directory")
    func textItemRoundTripsWhenPersisting() {
        let directory = makeTempDirectory()

        let first = ClipboardStore(directory: directory)
        first.persistsToDisk = { true }
        first.load()
        first.record(textItem("hello", hash: "a"))

        let second = ClipboardStore(directory: directory)
        second.persistsToDisk = { true }
        second.load()
        #expect(second.items.count == 1)
        if case let .text(string) = second.items.first?.kind {
            #expect(string == "hello")
        } else {
            Issue.record("Expected a text item")
        }
    }

    @Test("With persistence on, an image's bytes survive a fresh instance over the same directory")
    func imageItemRoundTripsWhenPersisting() {
        let directory = makeTempDirectory()

        let first = ClipboardStore(directory: directory)
        first.persistsToDisk = { true }
        first.load()
        first.record(imageItem(hash: "img"))

        let second = ClipboardStore(directory: directory)
        second.persistsToDisk = { true }
        second.load()
        #expect(second.items.count == 1)
        if case let .image(pngData, thumbnail) = second.items.first?.kind {
            #expect(pngData == Data([0x01, 0x02, 0x03]))
            #expect(thumbnail == Data([0x04]))
        } else {
            Issue.record("Expected an image item")
        }
    }

    @Test("Removing an item deletes its blob files, so a reload doesn't resurrect it")
    func removingDeletesBlobFiles() {
        let directory = makeTempDirectory()

        let store = ClipboardStore(directory: directory)
        store.persistsToDisk = { true }
        store.load()
        let item = imageItem(hash: "img")
        store.record(item)
        #expect(store.items.count == 1)

        store.remove(item)
        #expect(store.items.isEmpty)

        let reloaded = ClipboardStore(directory: directory)
        reloaded.persistsToDisk = { true }
        reloaded.load()
        #expect(reloaded.items.isEmpty)
    }

    @Test("Clearing removes every item and its blob files")
    func clearRemovesEverything() {
        let directory = makeTempDirectory()

        let store = ClipboardStore(directory: directory)
        store.persistsToDisk = { true }
        store.load()
        store.record(textItem("a", hash: "a"))
        store.record(imageItem(hash: "b"))
        #expect(store.items.count == 2)

        store.clear()
        #expect(store.items.isEmpty)

        let reloaded = ClipboardStore(directory: directory)
        reloaded.persistsToDisk = { true }
        reloaded.load()
        #expect(reloaded.items.isEmpty)
    }

    @Test("Loading with nothing on disk leaves an empty store rather than failing")
    func loadWithNothingOnDiskIsEmpty() {
        let store = ClipboardStore(directory: makeTempDirectory())
        store.load()
        #expect(store.items.isEmpty)
    }

    // MARK: - Purging (turning the feature off)

    @Test("Purging empties the store even while persistence is on, and nothing comes back on reload")
    func purgeRemovesEverythingRegardlessOfPersistence() {
        let directory = makeTempDirectory()

        let store = ClipboardStore(directory: directory)
        store.persistsToDisk = { true }
        store.load()
        let item = imageItem(hash: "img")
        store.record(item)
        #expect(store.items.count == 1)
        #expect(FileManager.default.fileExists(atPath: blobPath(directory, item.id)))

        store.purge()
        #expect(store.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: blobPath(directory, item.id)))

        let reloaded = ClipboardStore(directory: directory)
        reloaded.load()
        #expect(reloaded.items.isEmpty)
    }

    @Test("A stale ledger from when persistence used to be on doesn't survive clear(), even with persistence now off")
    func clearDeletesStaleLedgerAfterPersistenceIsTurnedOff() {
        let directory = makeTempDirectory()

        let store = ClipboardStore(directory: directory)
        store.persistsToDisk = { true }
        store.load()
        store.record(textItem("hello", hash: "a"))

        // The setting is now off, the way `applyClipboardEnabled` leaves it —
        // `clear()` still has to remove what an earlier, persisting session
        // wrote.
        store.persistsToDisk = { false }
        store.clear()

        let reloaded = ClipboardStore(directory: directory)
        reloaded.load()
        #expect(reloaded.items.isEmpty)
    }

    @Test("Clearing deletes an image item's blob files from disk, not just its ledger entry")
    func clearDeletesImageBlobFiles() {
        let directory = makeTempDirectory()

        let store = ClipboardStore(directory: directory)
        store.persistsToDisk = { true }
        store.load()
        let item = imageItem(hash: "img")
        store.record(item)
        #expect(FileManager.default.fileExists(atPath: blobPath(directory, item.id)))
        #expect(FileManager.default.fileExists(atPath: thumbnailBlobPath(directory, item.id)))

        store.clear()
        #expect(!FileManager.default.fileExists(atPath: blobPath(directory, item.id)))
        #expect(!FileManager.default.fileExists(atPath: thumbnailBlobPath(directory, item.id)))
    }

    @Test("An image dropped off the tail by the ledger's own count cap has its blob deleted too")
    func droppedImageOverCapHasItsBlobDeleted() {
        let directory = makeTempDirectory()

        let store = ClipboardStore(directory: directory)
        store.persistsToDisk = { true }
        store.load()

        let oldest = imageItem(hash: "0")
        store.record(oldest)
        #expect(FileManager.default.fileExists(atPath: blobPath(directory, oldest.id)))

        // One more than the cap allows, so `oldest` — the first one in,
        // sitting at the tail once every later copy lands ahead of it — is
        // the one the ledger's own count cap pushes out.
        for index in 1...ClipboardLedger.maximumCount {
            store.record(imageItem(hash: "\(index)"))
        }

        #expect(store.items.count == ClipboardLedger.maximumCount)
        #expect(!store.items.contains { $0.id == oldest.id })
        #expect(!FileManager.default.fileExists(atPath: blobPath(directory, oldest.id)))
    }

    // MARK: - Private

    /// Mirrors `ClipboardStore`'s own (private) blob-naming convention, so a
    /// test can check a blob file's presence on disk directly rather than
    /// only inferring it from what a reload brings back.
    private func blobPath(_ directory: URL, _ id: UUID) -> String {
        directory.appendingPathComponent("\(id.uuidString).png").path
    }

    private func thumbnailBlobPath(_ directory: URL, _ id: UUID) -> String {
        directory.appendingPathComponent("\(id.uuidString)-thumb.png").path
    }
}
