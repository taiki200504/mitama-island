import Foundation

/// One thing put aside in the island.
///
/// The file itself is copied rather than referenced. A shelf that holds paths
/// is a shelf that empties itself every time you tidy up a folder — the whole
/// point is that what you put down stays put down.
public struct ShelfItem: Equatable, Identifiable, Codable, Sendable {
    public let id: UUID
    /// What to show. The name the file had when it arrived.
    public let displayName: String
    /// What it is called inside the shelf's own folder, after collisions are
    /// resolved. Two files called `notes.md` must both survive.
    public let storedName: String
    public let byteSize: Int64
    public let addedAt: Date

    public init(
        id: UUID = UUID(),
        displayName: String,
        storedName: String,
        byteSize: Int64,
        addedAt: Date
    ) {
        self.id = id
        self.displayName = displayName
        self.storedName = storedName
        self.byteSize = byteSize
        self.addedAt = addedAt
    }
}

/// The rules of the shelf, with no filesystem attached.
public enum ShelfLedger: Sendable {
    /// Why something could not be put down.
    public enum Refusal: Equatable, Sendable {
        case full(usedBytes: Int64)
        case tooMany(count: Int)
        case tooLarge(byteSize: Int64)

        public var noticeKey: String {
            switch self {
            case .full: "shelf.refusal.full"
            case .tooMany: "shelf.refusal.tooMany"
            case .tooLarge: "shelf.refusal.tooLarge"
            }
        }
    }

    /// Deliberately modest. This is a place to put something down on the way
    /// somewhere else, not a second Downloads folder — and everything here is a
    /// second copy of a file that already exists somewhere.
    public static let maximumTotalBytes: Int64 = 2 * 1024 * 1024 * 1024
    public static let maximumCount = 50
    /// One enormous file would fill the shelf on its own.
    public static let maximumItemBytes: Int64 = 1024 * 1024 * 1024

    public static func totalBytes(_ items: [ShelfItem]) -> Int64 {
        items.reduce(0) { $0 + $1.byteSize }
    }

    /// Nil when there is room.
    public static func refusal(adding byteSize: Int64, to items: [ShelfItem]) -> Refusal? {
        if byteSize > maximumItemBytes { return .tooLarge(byteSize: byteSize) }
        if items.count >= maximumCount { return .tooMany(count: items.count) }
        let used = totalBytes(items)
        if used + byteSize > maximumTotalBytes { return .full(usedBytes: used) }
        return nil
    }

    /// A name no other item is already using.
    ///
    /// Numbers go before the extension so the file still opens in the right
    /// app — `notes 2.md`, never `notes.md 2`.
    public static func uniqueStoredName(for name: String, taken: Set<String>) -> String {
        guard taken.contains(name) else { return name }

        let url = URL(fileURLWithPath: name)
        let ext = url.pathExtension
        let stem = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))

        var index = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            if !taken.contains(candidate) { return candidate }
            index += 1
        }
    }

    /// Newest first — the thing you just put down is the thing you are about to
    /// pick up again.
    public static func ordered(_ items: [ShelfItem]) -> [ShelfItem] {
        items.sorted { $0.addedAt > $1.addedAt }
    }
}
