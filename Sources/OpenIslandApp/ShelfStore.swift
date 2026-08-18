import AppKit
import Foundation
import Observation
import OpenIslandCore
import os

/// Holds what you put down in the island, on disk.
///
/// Files are copied in rather than referenced. A shelf of paths empties itself
/// the first time you tidy a folder, and the point of putting something down is
/// that it stays down — the copy survives the original being moved, renamed or
/// deleted.
///
/// Nothing here is a background job: the shelf changes only when you drop
/// something on it or take something off it.
@MainActor
@Observable
final class ShelfStore {
    private static let logger = Logger(subsystem: "com.mitama.island", category: "shelf")

    private(set) var items: [ShelfItem] = []

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        directory = base.appending(path: "MitamaIsland/Shelf")
    }

    var totalBytes: Int64 { ShelfLedger.totalBytes(items) }
    var isEmpty: Bool { items.isEmpty }

    /// Reads the ledger, then drops anything the ledger claims but the disk no
    /// longer has. The two can part ways — a crash between copy and save, or
    /// someone clearing Application Support by hand.
    func load() {
        guard let data = try? Data(contentsOf: ledgerURL),
              let saved = try? JSONDecoder().decode([ShelfItem].self, from: data) else {
            items = []
            return
        }
        items = ShelfLedger.ordered(saved.filter { fileManager.fileExists(atPath: fileURL(for: $0).path) })
        if items.count != saved.count { save() }
    }

    /// Copies files onto the shelf. Returns the first refusal, if the shelf
    /// could not take everything.
    @discardableResult
    func accept(_ urls: [URL]) -> ShelfLedger.Refusal? {
        var refusal: ShelfLedger.Refusal?
        var changed = false

        for url in urls {
            let size = byteSize(of: url)
            if let reason = ShelfLedger.refusal(adding: size, to: items) {
                // Report the first reason and stop. Carrying on would copy a
                // small file after refusing a large one, which reads as random.
                refusal = reason
                break
            }
            guard let item = copyIn(url, byteSize: size) else { continue }
            items.insert(item, at: 0)
            changed = true
        }

        if changed { save() }
        return refusal
    }

    func remove(_ item: ShelfItem) {
        try? fileManager.removeItem(at: fileURL(for: item))
        items.removeAll { $0.id == item.id }
        save()
    }

    func removeAll() {
        for item in items { try? fileManager.removeItem(at: fileURL(for: item)) }
        items = []
        save()
    }

    /// Where the copy lives. Dragging out of the island hands this URL over.
    func fileURL(for item: ShelfItem) -> URL {
        directory.appending(path: item.storedName)
    }

    // MARK: - Private

    private var ledgerURL: URL { directory.appending(path: "shelf.json") }

    private func copyIn(_ url: URL, byteSize: Int64) -> ShelfItem? {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let storedName = ShelfLedger.uniqueStoredName(
                for: url.lastPathComponent,
                taken: Set(items.map(\.storedName))
            )
            try fileManager.copyItem(at: url, to: directory.appending(path: storedName))
            return ShelfItem(
                displayName: url.lastPathComponent,
                storedName: storedName,
                byteSize: byteSize,
                addedAt: Date()
            )
        } catch {
            Self.logger.notice(
                "Could not shelve \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            return nil
        }
    }

    /// Directories report nothing useful from `fileSize`, so they are measured
    /// by what they contain — a folder dropped on the shelf still has to count
    /// against the limit.
    private func byteSize(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        if values?.isDirectory == true {
            guard let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey]
            ) else { return 0 }
            var total: Int64 = 0
            for case let child as URL in enumerator {
                total += Int64((try? child.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            }
            return total
        }
        return Int64(values?.fileSize ?? 0)
    }

    private func save() {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(items).write(to: ledgerURL, options: .atomic)
        } catch {
            Self.logger.notice("Could not save the shelf: \(String(describing: error), privacy: .public)")
        }
    }
}
