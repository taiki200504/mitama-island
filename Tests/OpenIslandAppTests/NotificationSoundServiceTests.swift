import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

@MainActor
struct NotificationSoundServiceTests {
    private func makeTempLibrary() -> CustomSoundLibrary {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotificationSoundServiceTests-\(UUID().uuidString)")
        return CustomSoundLibrary(directory: directory)
    }

    /// A name with nothing imported and no matching bundled file falls all
    /// the way through to a system sound lookup — this is that fall-through
    /// case, confirmed by there being no resolved URL at all.
    @Test
    func aNameWithNoFileResolvesToNothing() {
        let library = makeTempLibrary()
        #expect(NotificationSoundService.resolvedSoundURL(named: "Glass", customLibrary: library) == nil)
    }

    @Test
    func aBundledCueResolvesToAFileWhenNothingIsImported() {
        let library = makeTempLibrary()
        let url = NotificationSoundService.resolvedSoundURL(named: "ui-open", customLibrary: library)
        #expect(url?.lastPathComponent == "ui-open.caf")
    }

    /// The whole point of importing a sound: picking "ui-open" for yourself
    /// has to win over the app's own bundled "ui-open".
    @Test
    func anImportedSoundWinsOverABundledCueOfTheSameName() throws {
        let library = makeTempLibrary()
        try FileManager.default.createDirectory(at: library.directory, withIntermediateDirectories: true)
        let importedURL = library.directory.appendingPathComponent("ui-open.wav")
        try Data([0x00]).write(to: importedURL)

        // Compared by resolved path rather than by URL: macOS's temporary
        // directory is reached through a `/var` symlink into `/private/var`,
        // and `FileManager.contentsOfDirectory` returns the resolved form —
        // a mismatch that has nothing to do with which file actually won.
        let resolved = NotificationSoundService.resolvedSoundURL(named: "ui-open", customLibrary: library)
        #expect(resolved?.resolvingSymlinksInPath().path == importedURL.resolvingSymlinksInPath().path)
    }

    @Test
    func everyBundledCueNameUsedByThemeResolves() {
        let library = makeTempLibrary()
        for event in NotificationSoundEvent.allCases {
            let name = IslandSoundProfile.sao.soundName(for: event)
            guard name.hasPrefix("ui-") else { continue }
            #expect(NotificationSoundService.resolvedSoundURL(named: name, customLibrary: library) != nil)
        }
    }

    // MARK: - availableSounds de-duplication

    /// A user importing a file with the same stem as a bundled cue used to
    /// leave that name in the list twice, which is what broke
    /// `ForEach(id: \.self)` in the sound picker.
    @Test
    func aNameInBothTheBundleAndImportsAppearsOnlyOnce() throws {
        let library = makeTempLibrary()
        try FileManager.default.createDirectory(at: library.directory, withIntermediateDirectories: true)
        try Data([0x00]).write(to: library.directory.appendingPathComponent("ui-open.wav"))

        let names = NotificationSoundService.availableSounds(customLibrary: library)
        #expect(names.filter { $0 == "ui-open" }.count == 1)
        #expect(Set(names).count == names.count)
    }

    // MARK: - Fire points

    /// A notification card already plays its own event chime
    /// (`presentNotificationSurface`) right before opening the notch. This
    /// confirms the open itself stays silent so the two do not stack into a
    /// double chime.
    @Test
    func aNotificationOpenDoesNotAlsoPlayTheOpenCue() {
        let model = AppModel()
        model.state = SessionState(sessions: [
            AgentSession(
                id: "s1",
                title: "Claude · demo",
                tool: .claudeCode,
                origin: .live,
                attachmentState: .attached,
                phase: .waitingForApproval,
                summary: "waiting",
                updatedAt: Date()
            ),
        ])
        model.notchStatus = .closed
        model.notchOpenReason = nil

        var played: [String] = []
        NotificationSoundService.harnessSink = { played.append($0) }
        defer { NotificationSoundService.harnessSink = nil }

        model.overlay.presentNotificationSurface(.sessionList(actionableSessionID: "s1"))

        #expect(played == ["sound.cue=ui-notify"])
    }
}
