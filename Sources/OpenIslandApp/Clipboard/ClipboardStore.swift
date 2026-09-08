import AppKit
import Foundation
import Observation
import OpenIslandCore
import os

/// Holds the clipboard history in memory, and — only when the setting asks
/// for it — on disk.
///
/// Off by default (see `ClipboardSettings.enabled`): nothing here runs, and
/// nothing is written anywhere, until the person turns it on. Once running,
/// persistence is itself a second, independent switch
/// (`ClipboardSettings.persistsToDisk`) — remembering copies across a relaunch
/// is a stronger claim than remembering them for the current session, and a
/// password-manager miss that the in-session privacy filter didn't catch is a
/// one-session mistake instead of a permanent one.
@MainActor
@Observable
final class ClipboardStore {
    private static let logger = Logger(subsystem: "com.mitama.island", category: "clipboard")

    private(set) var items: [ClipboardItem] = []

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let fileManager: FileManager
    @ObservationIgnored private let pasteboard: NSPasteboard

    /// Read fresh on every write rather than cached, the same reasoning
    /// `ShelfStore.expiryProvider` gives: a setting toggled while the store is
    /// already running takes effect on the very next copy instead of needing
    /// the store rebuilt.
    @ObservationIgnored var persistsToDisk: () -> Bool = { false }
    @ObservationIgnored var pastesOnSelectEnabled: () -> Bool = { false }

    /// Told about every write this store makes back to the pasteboard, so it
    /// can resync its own change count and not record its own copy as a new
    /// external one.
    @ObservationIgnored weak var watcher: PasteboardWatcher?

    init(
        directory: URL? = nil,
        fileManager: FileManager = .default,
        pasteboard: NSPasteboard = .general
    ) {
        self.fileManager = fileManager
        self.pasteboard = pasteboard
        if let directory {
            self.directory = directory
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.directory = base.appending(path: "MitamaIsland/Clipboard")
        }
    }

    var isEmpty: Bool { items.isEmpty }

    /// Reads whatever was saved last time. A no-op — leaves `items` empty —
    /// when there is nothing on disk, which is also what a fresh install and
    /// a session with persistence turned off both look like.
    func load() {
        guard let data = try? Data(contentsOf: ledgerURL),
              let persisted = try? JSONDecoder().decode([PersistedItem].self, from: data) else {
            items = []
            return
        }
        items = persisted.compactMap(reconstitute)
    }

    /// Adds a freshly copied item — how `AppModel+Clipboard` wires
    /// `PasteboardWatcher.onNewItem` in. Not `add(_:)` on any random item:
    /// production only ever calls this from that one place, so the ledger's
    /// own dedup-and-cap rule always runs on a real, just-copied item.
    ///
    /// Whatever the ledger's own cap or dedup rule pushed out — an image
    /// bumped off the tail, or a duplicate's older copy — has its blob files
    /// deleted here. Without this an image that fell off the end of the
    /// history would sit in `Application Support` forever, outliving every
    /// row that could ever point back to it.
    func record(_ item: ClipboardItem) {
        let previousIDs = Set(items.map(\.id))
        items = ClipboardLedger.inserting(item, into: items)
        let droppedIDs = previousIDs.subtracting(items.map(\.id))
        for id in droppedIDs { removeBlobs(for: id) }
        saveIfPersisting()
    }

    /// Writes the item back to the general pasteboard — a row tap's default
    /// action — and tells the watcher not to mistake this for a new copy.
    func copy(_ item: ClipboardItem) {
        pasteboard.clearContents()
        switch item.kind {
        case let .text(string):
            pasteboard.setString(string, forType: .string)
        case let .image(pngData, _):
            pasteboard.setData(pngData, forType: .png)
        case let .fileURLs(urls):
            pasteboard.writeObjects(urls.map { $0 as NSURL })
        }
        watcher?.resyncChangeCount()
    }

    /// Whether picking a row should also send a synthetic ⌘V — only true
    /// when the setting is on and Accessibility has actually been granted.
    /// Without that permission the event is silently dropped by macOS, which
    /// is worse than not trying: the row would look like it did nothing.
    /// `AppModel.selectClipboardItem` checks this to decide whether to defer
    /// a `postPasteKeystroke()` call until after the island has closed.
    var shouldPostPasteKeystroke: Bool {
        pastesOnSelectEnabled() && AXIsProcessTrusted()
    }

    /// Sends a synthetic ⌘V to whatever app is now frontmost.
    ///
    /// Deliberately a separate call from `copy(_:)`, not bundled into one
    /// "paste back" method: the caller has to close the island — and give
    /// the frontmost app back its focus — before this fires, or the
    /// keystroke lands on the island's own search field instead of wherever
    /// the user actually wanted to paste.
    func postPasteKeystroke() {
        let keyCode: CGKeyCode = 9
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            return
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    func remove(_ item: ClipboardItem) {
        items = ClipboardLedger.removing(id: item.id, from: items)
        removeBlobs(for: item.id)
        saveIfPersisting()
    }

    /// Removes everything, in memory and on disk — unconditionally, whether
    /// or not `persistsToDisk` is currently on. A stale `ledger.json` left
    /// over from a session where persistence used to be on is exactly the
    /// kind of thing "clear" and "turn the feature off" both promise to
    /// actually clear; gating this on the current setting would leave it
    /// sitting there, readable the next time persistence is switched back on.
    func clear() {
        for item in items { removeBlobs(for: item.id) }
        items = []
        try? fileManager.removeItem(at: ledgerURL)
    }

    /// Same wipe as `clear()`, under the name `AppModel+Clipboard` calls when
    /// the feature itself is switched off rather than when the user taps
    /// "Clear all" — turning the setting off has to mean nothing survives it,
    /// on disk or in memory, the same as it would for a fresh install.
    func purge() {
        clear()
    }

    /// Test and harness fixture loading: puts items in memory without
    /// touching the ledger file or copying anything in. Production code
    /// always goes through `record(_:)`.
    func loadFixture(_ items: [ClipboardItem]) {
        self.items = items
    }

    // MARK: - Private

    private var ledgerURL: URL { directory.appending(path: "ledger.json") }

    private func saveIfPersisting() {
        guard persistsToDisk() else { return }
        save()
    }

    private func save() {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let persisted = items.map(persist)
            try JSONEncoder().encode(persisted).write(to: ledgerURL, options: .atomic)
        } catch {
            Self.logger.notice("Could not save the clipboard history: \(String(describing: error), privacy: .public)")
        }
    }

    /// Text and file URLs are small enough to live inline in `ledger.json`.
    /// An image's PNG (and its thumbnail) go into their own files instead —
    /// keeping the ledger itself a quick, small read even with a handful of
    /// screenshots sitting in the history.
    private func persist(_ item: ClipboardItem) -> PersistedItem {
        switch item.kind {
        case let .text(string):
            return PersistedItem(
                id: item.id,
                kind: .text(string),
                sourceBundleID: item.sourceBundleID,
                copiedAt: item.copiedAt,
                contentHash: item.contentHash
            )
        case let .fileURLs(urls):
            return PersistedItem(
                id: item.id,
                kind: .fileURLs(urls),
                sourceBundleID: item.sourceBundleID,
                copiedAt: item.copiedAt,
                contentHash: item.contentHash
            )
        case let .image(pngData, thumbnail):
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try? pngData.write(to: blobURL(for: item.id), options: .atomic)
            if let thumbnail {
                try? thumbnail.write(to: thumbnailBlobURL(for: item.id), options: .atomic)
            }
            return PersistedItem(
                id: item.id,
                kind: .image(hasThumbnail: thumbnail != nil),
                sourceBundleID: item.sourceBundleID,
                copiedAt: item.copiedAt,
                contentHash: item.contentHash
            )
        }
    }

    /// The mirror of `persist(_:)`. An image whose blob went missing between
    /// sessions (Application Support cleared by hand, say) is dropped rather
    /// than shown as a broken row — the same call `ShelfStore.load()` makes
    /// for a shelf item whose copied file is gone.
    private func reconstitute(_ persisted: PersistedItem) -> ClipboardItem? {
        let kind: ClipboardItemKind
        switch persisted.kind {
        case let .text(string):
            kind = .text(string)
        case let .fileURLs(urls):
            kind = .fileURLs(urls)
        case let .image(hasThumbnail):
            guard let pngData = try? Data(contentsOf: blobURL(for: persisted.id)) else { return nil }
            let thumbnail = hasThumbnail ? try? Data(contentsOf: thumbnailBlobURL(for: persisted.id)) : nil
            kind = .image(pngData: pngData, thumbnail: thumbnail)
        }
        return ClipboardItem(
            id: persisted.id,
            kind: kind,
            sourceBundleID: persisted.sourceBundleID,
            copiedAt: persisted.copiedAt,
            contentHash: persisted.contentHash
        )
    }

    private func removeBlobs(for id: UUID) {
        try? fileManager.removeItem(at: blobURL(for: id))
        try? fileManager.removeItem(at: thumbnailBlobURL(for: id))
    }

    private func blobURL(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).png")
    }

    private func thumbnailBlobURL(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString)-thumb.png")
    }
}

/// The on-disk shape of a `ClipboardItem`. A separate type from
/// `ClipboardItemKind` rather than encoding that directly, so an image's
/// bytes never round-trip through the ledger file itself.
private struct PersistedItem: Codable {
    let id: UUID
    let kind: PersistedKind
    let sourceBundleID: String?
    let copiedAt: Date
    let contentHash: String

    enum PersistedKind: Codable {
        case text(String)
        case image(hasThumbnail: Bool)
        case fileURLs([URL])
    }
}
