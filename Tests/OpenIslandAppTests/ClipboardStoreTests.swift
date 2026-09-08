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
}
