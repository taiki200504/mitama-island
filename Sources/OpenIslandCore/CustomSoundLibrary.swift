import Foundation

/// Audio files the user added, kept alongside the macOS system sounds.
///
/// Files are copied into Application Support rather than referenced where they
/// were found. A sound that stops working because the folder it came from was
/// moved is a worse experience than the copy costing a few hundred kilobytes.
public struct CustomSoundLibrary {
    /// What `NSSound(contentsOf:)` will actually play.
    public static let supportedExtensions: Set<String> = ["aiff", "aif", "wav", "m4a", "mp3", "caf"]

    public let directory: URL
    private let fileManager: FileManager

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    public static func defaultDirectory(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appending(path: "MitamaIsland/Sounds")
    }

    /// Names, without extension, sorted the way a person would expect.
    public func soundNames() -> [String] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return contents
            .filter { Self.supportedExtensions.contains($0.pathExtension.lowercased()) }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public func url(forSoundNamed name: String) -> URL? {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }
        return contents.first {
            Self.supportedExtensions.contains($0.pathExtension.lowercased())
                && $0.deletingPathExtension().lastPathComponent == name
        }
    }

    /// Copies in every playable file found at `sources`, folders included.
    ///
    /// Returns the names that landed. Unreadable or unsupported files are
    /// skipped rather than failing the whole import — one bad file in a folder
    /// of twenty should not lose the other nineteen.
    @discardableResult
    public func importSounds(from sources: [URL]) throws -> [String] {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        var imported: [String] = []
        for source in expand(sources) {
            let destination = uniqueDestination(for: source)
            guard (try? fileManager.copyItem(at: source, to: destination)) != nil else { continue }
            imported.append(destination.deletingPathExtension().lastPathComponent)
        }
        return imported.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public func removeSound(named name: String) throws {
        guard let url = url(forSoundNamed: name) else { return }
        try fileManager.removeItem(at: url)
    }

    private func expand(_ sources: [URL]) -> [URL] {
        sources.flatMap { source -> [URL] in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory) else { return [] }
            guard isDirectory.boolValue else {
                return Self.supportedExtensions.contains(source.pathExtension.lowercased()) ? [source] : []
            }
            let contents = (try? fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)) ?? []
            return contents.filter { Self.supportedExtensions.contains($0.pathExtension.lowercased()) }
        }
    }

    /// Keeps a second `chime.wav` from silently replacing the first.
    private func uniqueDestination(for source: URL) -> URL {
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var candidate = directory.appending(path: "\(base).\(ext)")
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appending(path: "\(base) \(suffix).\(ext)")
            suffix += 1
        }
        return candidate
    }
}
