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

    /// How long an item may sit before `pruneExpired` takes it away. Nil —
    /// the default — means never. A closure rather than a stored value so the
    /// setting can change without anyone having to push the new value in.
    @ObservationIgnored var expiryProvider: () -> TimeInterval? = { nil }

    /// Owns the "come forward, then give focus back" dance around AirDrop and
    /// the share sheet. A separate object because `@objc` delegate protocols
    /// need an `NSObject`, which `ShelfStore` itself is not.
    @ObservationIgnored private let sharingFocusHandler = ShelfSharingFocusHandler()

    /// `directory` is injectable so a test can point the shelf at a scratch
    /// folder instead of the real one under Application Support.
    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let directory {
            self.directory = directory
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.directory = base.appending(path: "MitamaIsland/Shelf")
        }
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

    /// Drops whatever `expiryProvider` currently says has sat around too long.
    /// A no-op while the setting is at its default of never.
    @discardableResult
    func pruneExpired(now: Date = .now) -> [ShelfItem] {
        let stale = ShelfLedger.expired(items, now: now, ttl: expiryProvider())
        guard !stale.isEmpty else { return [] }
        for item in stale { try? fileManager.removeItem(at: fileURL(for: item)) }
        let staleIDs = Set(stale.map(\.id))
        items.removeAll { staleIDs.contains($0.id) }
        save()
        return stale
    }

    /// Hands the shelved copy to AirDrop directly, skipping the sharing menu.
    func airDrop(_ item: ShelfItem) {
        sharingFocusHandler.activateIfNeeded()
        let service = NSSharingService(named: .sendViaAirDrop)
        service?.delegate = sharingFocusHandler
        service?.perform(withItems: [fileURL(for: item)])
    }

    /// The full sharing picker — AirDrop plus whatever else macOS offers for
    /// this file type.
    func share(_ item: ShelfItem, from view: NSView) {
        sharingFocusHandler.activateIfNeeded()
        let picker = NSSharingServicePicker(items: [fileURL(for: item)])
        picker.delegate = sharingFocusHandler
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    /// Test and harness fixture loading: puts items in memory without
    /// touching the ledger or copying anything in. Production code always
    /// goes through `accept`.
    func loadFixture(_ items: [ShelfItem]) {
        self.items = ShelfLedger.ordered(items)
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

/// Brings the app forward long enough to show AirDrop or the share sheet, then
/// hands focus back to whatever had it — the island's panel never becomes the
/// active application on its own, the same problem `LinkstartOverlayController`
/// solves for its own overlay by remembering and restoring the frontmost app.
@MainActor
private final class ShelfSharingFocusHandler: NSObject, @MainActor NSSharingServiceDelegate, @MainActor NSSharingServicePickerDelegate {
    private var returnFocusTo: NSRunningApplication?

    func activateIfNeeded() {
        guard !NSApp.isActive else { return }
        returnFocusTo = NSWorkspace.shared.frontmostApplication
        NSApp.activate()
    }

    private func restoreFocus() {
        guard let returnFocusTo, !returnFocusTo.isTerminated else { return }
        returnFocusTo.activate()
        self.returnFocusTo = nil
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        restoreFocus()
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        restoreFocus()
    }

    /// Fires once the picker itself closes. A cancellation (`nil`) is the
    /// picker's only word on the matter, so focus returns right here; a real
    /// choice hands off to that service's own delegate callback instead.
    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        guard let service else {
            restoreFocus()
            return
        }
        service.delegate = self
    }
}

/// How long something may sit on the shelf before it disappears on its own.
///
/// A raw string so an unknown future value falls back rather than failing to
/// decode, the same reason `AgentIconStyle` is stored this way.
enum ShelfExpiryOption: String, CaseIterable, Identifiable, Sendable {
    case never
    case oneHour
    case oneDay
    case sevenDays

    var id: String { rawValue }
    var labelKey: String { "settings.display.shelfExpiresAfter.\(rawValue)" }

    /// Nil means never — this option's own default, and the shelf's behaviour
    /// before this setting existed.
    var ttl: TimeInterval? {
        switch self {
        case .never: nil
        case .oneHour: 3600
        case .oneDay: 86400
        case .sevenDays: 7 * 86400
        }
    }
}
