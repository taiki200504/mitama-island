import Foundation

/// Persistent storage for Resume Cards.
///
/// Cards are stored as JSONL (newline-delimited JSON) in a local file,
/// similar to how session transcripts are stored. This ensures:
/// - Local-first: no cloud, no network, no external services
/// - Durability: survives app restart and macOS restarts
/// - Privacy: no data leaves the machine
///
/// Default location: `~/Library/Application Support/Open Island/resume_cards.jsonl`
public actor ResumeCardStore {
    private let fileURL: URL
    private var cache: FocusCardState = FocusCardState()
    private var isInitialized = false

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    /// Default location for Resume Card storage.
    public static func defaultFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appDir = appSupport.appendingPathComponent("Open Island", isDirectory: true)
        return appDir.appendingPathComponent("resume_cards.jsonl")
    }

    /// Load all Resume Cards from disk into memory.
    /// Call this once on app startup.
    public func load() async throws {
        guard !isInitialized else { return }

        // Ensure directory exists
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            cache = FocusCardState()
            isInitialized = true
            // Create empty file for future writes
            try? "".write(to: fileURL, atomically: true, encoding: .utf8)
            return
        }

        let data = try Data(contentsOf: fileURL)
        let lines = String(data: data, encoding: .utf8)?
            .split(separator: "\n")
            .filter { !$0.isEmpty }
            .map { String($0) } ?? []

        var cards: [ResumeCard] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for line in lines {
            if let card = try? decoder.decode(ResumeCard.self, from: Data(line.utf8)) {
                cards.append(card)
            }
        }

        // Sort by most recent first
        cache.history = cards.sorted { $0.savedAt > $1.savedAt }
        isInitialized = true
    }

    /// Save a new Resume Card and update the current card.
    public func save(_ card: ResumeCard) async throws {
        try await ensureInitialized()

        cache.save(card)

        // Append to file
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = try encoder.encode(card)
        let line = String(data: json, encoding: .utf8) ?? ""

        let fileHandle = try FileHandle(forWritingTo: fileURL)
        defer { try? fileHandle.close() }
        fileHandle.seekToEndOfFile()
        if let data = "\n\(line)".data(using: .utf8) {
            fileHandle.write(data)
        }
    }

    /// Get the current Resume Card, if one exists.
    public func current() async throws -> ResumeCard? {
        try await ensureInitialized()
        return cache.currentCard
    }

    /// Get all Resume Cards from history.
    public func history() async throws -> [ResumeCard] {
        try await ensureInitialized()
        return cache.history
    }

    /// Resume from a card and update it as the current card.
    public func resume(_ card: ResumeCard) async throws {
        try await ensureInitialized()
        cache.resume(card)
    }

    /// Dismiss the current card without resuming.
    public func dismissCurrent() async throws {
        try await ensureInitialized()
        cache.dismissCurrent()
    }

    /// Remove cards older than 7 days (default).
    public func pruneOldCards() async throws {
        try await ensureInitialized()
        cache.pruneOldCards(olderThan: 7 * 24 * 3600)
    }

    // MARK: - Private

    private func ensureInitialized() async throws {
        if !isInitialized {
            try await load()
        }
    }
}
