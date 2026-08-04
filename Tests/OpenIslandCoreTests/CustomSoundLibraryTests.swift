import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Custom sound library")
struct CustomSoundLibraryTests {
    private func makeLibrary() throws -> (CustomSoundLibrary, URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "sounds-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (CustomSoundLibrary(directory: root.appending(path: "library")), root)
    }

    private func write(_ name: String, in directory: URL) throws -> URL {
        let url = directory.appending(path: name)
        try Data("audio".utf8).write(to: url)
        return url
    }

    @Test("Imported files become selectable by name")
    func importsFiles() throws {
        let (library, root) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try write("chime.wav", in: root)

        #expect(try library.importSounds(from: [source]) == ["chime"])
        #expect(library.soundNames() == ["chime"])
        #expect(library.url(forSoundNamed: "chime") != nil)
    }

    @Test("A folder brings in every playable file inside it")
    func importsFolders() throws {
        let (library, root) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "pack")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = try write("a.wav", in: folder)
        _ = try write("b.aiff", in: folder)

        #expect(try library.importSounds(from: [folder]) == ["a", "b"])
    }

    /// One unsupported file in a folder must not lose the rest.
    @Test("Unplayable files are skipped, not fatal")
    func skipsUnsupported() throws {
        let (library, root) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "pack")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = try write("notes.txt", in: folder)
        _ = try write("good.wav", in: folder)

        #expect(try library.importSounds(from: [folder]) == ["good"])
    }

    /// Two files called `chime.wav` from different folders are two sounds.
    /// Overwriting silently would lose the one the user imported first.
    @Test("A repeated name does not overwrite")
    func keepsBothOnNameClash() throws {
        let (library, root) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appending(path: "one")
        let second = root.appending(path: "two")
        for folder in [first, second] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            _ = try write("chime.wav", in: folder)
        }

        _ = try library.importSounds(from: [first.appending(path: "chime.wav")])
        _ = try library.importSounds(from: [second.appending(path: "chime.wav")])
        #expect(library.soundNames() == ["chime", "chime 2"])
    }

    @Test("Removing takes the file with it")
    func removes() throws {
        let (library, root) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try library.importSounds(from: [try write("chime.wav", in: root)])

        try library.removeSound(named: "chime")
        #expect(library.soundNames().isEmpty)
    }

    @Test("An empty library reads as empty, not as an error")
    func emptyLibrary() throws {
        let (library, root) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(library.soundNames().isEmpty)
        #expect(library.url(forSoundNamed: "anything") == nil)
    }
}
