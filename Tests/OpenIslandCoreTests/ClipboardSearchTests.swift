import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Clipboard search")
struct ClipboardSearchTests {
    private func textItem(_ text: String) -> ClipboardItem {
        .init(kind: .text(text), sourceBundleID: nil, copiedAt: .now, contentHash: text)
    }

    private func fileItem(_ names: [String]) -> ClipboardItem {
        .init(
            kind: .fileURLs(names.map { URL(fileURLWithPath: "/tmp/\($0)") }),
            sourceBundleID: nil,
            copiedAt: .now,
            contentHash: names.joined()
        )
    }

    private func imageItem() -> ClipboardItem {
        .init(kind: .image(pngData: Data(), thumbnail: nil), sourceBundleID: nil, copiedAt: .now, contentHash: "img")
    }

    @Test("An empty query returns everything, unfiltered")
    func emptyQueryReturnsEverything() {
        let items = [textItem("hello"), textItem("world")]
        #expect(ClipboardSearch.filter(items, query: "").count == 2)
        #expect(ClipboardSearch.filter(items, query: "   ").count == 2)
    }

    @Test("A substring match on text is case-insensitive")
    func textMatchIsCaseInsensitive() {
        let items = [textItem("Hello World")]
        #expect(ClipboardSearch.filter(items, query: "hello").count == 1)
        #expect(ClipboardSearch.filter(items, query: "WORLD").count == 1)
        #expect(ClipboardSearch.filter(items, query: "goodbye").isEmpty)
    }

    @Test("A substring match on text is diacritic-insensitive")
    func textMatchIsDiacriticInsensitive() {
        let items = [textItem("café")]
        #expect(ClipboardSearch.filter(items, query: "cafe").count == 1)
    }

    @Test("A file item matches on its last path component")
    func fileItemMatchesFileName() {
        let items = [fileItem(["quarterly-report.pdf"])]
        #expect(ClipboardSearch.filter(items, query: "quarterly").count == 1)
        #expect(ClipboardSearch.filter(items, query: "nomatch").isEmpty)
    }

    @Test("An image never matches a non-empty query — there is no text to search")
    func imageNeverMatchesNonEmptyQuery() {
        let items = [imageItem()]
        #expect(ClipboardSearch.filter(items, query: "anything").isEmpty)
    }

    @Test("An image is included when the query is empty")
    func imageIsIncludedForEmptyQuery() {
        let items = [imageItem()]
        #expect(ClipboardSearch.filter(items, query: "").count == 1)
    }
}
