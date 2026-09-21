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
    /// 固定した時刻。nil なら固定していない。
    ///
    /// `Bool` ではなく `Optional` の日付なのは2つ理由がある。並べ替えの鍵が
    /// そのまま要ること、そして**古い棚を読み直せること**——合成された
    /// Decodable は既定値に落ちてくれないので、`Bool` を足すと欄の無い
    /// 既存のファイルが丸ごと読めなくなる。
    public var pinnedAt: Date?

    public var isPinned: Bool { pinnedAt != nil }

    public init(
        id: UUID = UUID(),
        displayName: String,
        storedName: String,
        byteSize: Int64,
        addedAt: Date,
        pinnedAt: Date? = nil
    ) {
        self.id = id
        self.pinnedAt = pinnedAt
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
    /// pick up again。ただし固定したものは、いつ置いたかに関わらず上に浮く。
    public static func ordered(_ items: [ShelfItem]) -> [ShelfItem] {
        items.sorted { lhs, rhs in
            switch (lhs.pinnedAt, rhs.pinnedAt) {
            case let (left?, right?): return left > right
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return lhs.addedAt > rhs.addedAt
            }
        }
    }

    /// What has sat around longer than `ttl` allows. `ttl == nil` — the
    /// default — means never, so nothing here ever comes back expired.
    /// 固定したものは失効しない。置いたままにしておくために固定したのに、
    /// 時間で消えるなら固定の意味が無い。
    public static func expired(_ items: [ShelfItem], now: Date, ttl: TimeInterval?) -> [ShelfItem] {
        guard let ttl else { return [] }
        return items.filter { !$0.isPinned && now.timeIntervalSince($0.addedAt) >= ttl }
    }
}

/// What the drop invitation should tell the user, purely as data.
///
/// Pulled out of the view for the same reason `ShelfLedger` was: whether a
/// drag is worth a warning is a decision, and a decision belongs somewhere it
/// can be checked without a screen.
public enum ShelfDropFeedback: Sendable {
    public enum State: Equatable, Sendable {
        /// Nothing is being dragged over the shelf.
        case idle
        /// Files are hovering and would be accepted.
        case invited(count: Int)
        /// Files are hovering, but the shelf already knows it would refuse them.
        case refused(ShelfLedger.Refusal)
    }

    /// `count` is how many files are currently hovering; `bytes` is their
    /// combined size, if known. A hover with nothing yet known about size just
    /// invites — the refusal, if any, shows once the drop is actually
    /// attempted and `ShelfStore.accept` has real numbers to check.
    public static func state(
        hoveringCount count: Int,
        addingBytes bytes: Int64? = nil,
        over items: [ShelfItem] = []
    ) -> State {
        guard count > 0 else { return .idle }
        if let bytes, let refusal = ShelfLedger.refusal(adding: bytes, to: items) {
            return .refused(refusal)
        }
        return .invited(count: count)
    }
}
