import Foundation
import Testing
@testable import OpenIslandApp

@Suite struct AmbientVideoFolderTests {
    @Test("A custom path is used verbatim rather than falling back to the default folder")
    func customPathOverridesDefault() {
        let custom = "/Users/example/Movies/Ambient"
        #expect(AmbientVideoFolder.directory(customPath: custom).path == custom)
    }

    @Test("An empty path resolves to the default Application Support folder")
    func emptyPathResolvesToDefault() {
        let directory = AmbientVideoFolder.directory(customPath: "")
        #expect(directory.path.hasSuffix("MitamaIsland/Ambient"))
    }

    @Test("Listing a folder with real files returns only the videos, sorted by name")
    func listsOnlyVideoFiles() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ambient-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: root.appending(path: "b.mov"))
        try Data().write(to: root.appending(path: "a.mp4"))
        try Data().write(to: root.appending(path: "notes.txt"))

        let videos = AmbientVideoFolder.availableVideos(customPath: root.path)
        #expect(videos.map(\.lastPathComponent) == ["a.mp4", "b.mov"])
    }

    @Test("A folder that does not exist yet is created rather than failing")
    func missingFolderIsCreatedOnDemand() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ambient-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(AmbientVideoFolder.availableVideos(customPath: root.path).isEmpty)
        #expect(FileManager.default.fileExists(atPath: root.path))
    }
}
