import AppKit
import CryptoKit
import Foundation
import OpenIslandCore

/// Notices when something new lands on the general pasteboard and turns it
/// into a `ClipboardItem`.
///
/// Polls `NSPasteboard.general.changeCount` rather than registering for a
/// notification — AppKit has never offered one, since any process on the
/// system can write to the pasteboard at any time. A 0.5s interval is
/// frequent enough that a copy-then-paste a moment later never sees a stale
/// history, and light enough to leave running for as long as the setting is on.
@MainActor
final class PasteboardWatcher {
    private let pasteboard: NSPasteboard
    private let timerBox = RepeatingTimerBox()
    private var lastChangeCount: Int

    var onNewItem: ((ClipboardItem) -> Void)?

    /// Swappable for tests and for the harness — production reads the real
    /// frontmost app and the real lock state.
    var frontmostBundleID: () -> String? = {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
    var isLocked: () -> Bool = { QuietSceneMonitor.readScreenLock() }
    var denyList: () -> Set<String> = { ClipboardPrivacy.defaultDenyList }

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timerBox.timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        timer.tolerance = 0.15
        timerBox.timer = timer
    }

    func stop() {
        timerBox.invalidate()
    }

    /// Called right after `ClipboardStore` writes back to the pasteboard
    /// itself (a row tapped to copy, or a paste-back) — without this, the
    /// next poll would see its own write as a new external copy and record
    /// the same item a second time.
    func resyncChangeCount() {
        lastChangeCount = pasteboard.changeCount
    }

    private func poll() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard let item = readItem() else { return }
        onNewItem?(item)
    }

    private func readItem() -> ClipboardItem? {
        let types = (pasteboard.types ?? []).map(\.rawValue)
        let bundleID = frontmostBundleID()
        guard !ClipboardPrivacy.shouldSkip(
            types: types,
            frontmostBundleID: bundleID,
            isLocked: isLocked(),
            denyList: denyList()
        ) else {
            return nil
        }

        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            return ClipboardItem(
                kind: .fileURLs(urls),
                sourceBundleID: bundleID,
                copiedAt: .now,
                contentHash: Self.hash(urls.map(\.absoluteString).joined(separator: "\n"))
            )
        }

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return ClipboardItem(
                kind: .text(text),
                sourceBundleID: bundleID,
                copiedAt: .now,
                contentHash: Self.hash(text)
            )
        }

        if let pngData = imagePNGData() {
            return ClipboardItem(
                kind: .image(pngData: pngData, thumbnail: Self.thumbnail(from: pngData)),
                sourceBundleID: bundleID,
                copiedAt: .now,
                contentHash: Self.hash(pngData)
            )
        }

        return nil
    }

    /// Reads whatever image the pasteboard is carrying — PNG or TIFF, the
    /// two forms an app is likely to have put there — and re-encodes it as
    /// PNG so every stored item shares one format.
    private func imagePNGData() -> Data? {
        if let data = pasteboard.data(forType: .png) {
            return data
        }
        guard let tiffData = pasteboard.data(forType: .tiff),
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    /// A 64pt-max thumbnail for the row — the full image is kept for
    /// paste-back, but drawing that at row height on every scroll would be
    /// wasteful.
    private static func thumbnail(from pngData: Data, maxDimension: CGFloat = 64) -> Data? {
        guard let image = NSImage(data: pngData) else { return nil }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        let scale = min(1, maxDimension / max(size.width, size.height))
        let targetSize = NSSize(width: size.width * scale, height: size.height * scale)

        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1
        )
        thumbnail.unlockFocus()

        guard let tiff = thumbnail.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func hash(_ string: String) -> String {
        hash(Data(string.utf8))
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
