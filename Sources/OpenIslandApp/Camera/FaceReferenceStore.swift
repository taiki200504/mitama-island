import Foundation
import OpenIslandCore

/// Where the enrolled face lives on disk.
///
/// Feature vectors only — the frames they were derived from are never written
/// anywhere. Kept out of the app's preferences on purpose: a face belongs in a
/// file the user can point at and delete, not buried in a defaults plist.
struct FaceReferenceStore: Sendable {
    let fileURL: URL

    static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("Open Island", isDirectory: true)
            .appendingPathComponent("face-reference.json")
    }

    init(fileURL: URL = FaceReferenceStore.defaultURL()) {
        self.fileURL = fileURL
    }

    /// Nil covers both "never enrolled" and "the file is unreadable". Neither is
    /// an error worth surfacing: the answer in both cases is to enrol again.
    func load() -> FaceReference? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? FaceReference(jsonData: data)
    }

    func save(_ reference: FaceReference) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try reference.encodedJSON().write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    var hasReference: Bool { load()?.representativeVector != nil }
}
