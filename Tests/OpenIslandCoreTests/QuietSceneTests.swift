import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Quiet scene policy")
struct QuietScenePolicyTests {
    @Test("Nothing is suppressed when no switch is on")
    func silentByDefault() {
        let scene = QuietSceneSnapshot(
            activeFocusModes: ["work"],
            screenIsObscured: .active,
            screenIsBeingShared: .active
        )
        #expect(QuietScenePolicy().shouldStayQuiet(in: scene) == false)
    }

    @Test("A matching focus mode suppresses")
    func focusMatch() {
        let policy = QuietScenePolicy(quietFocusModes: ["work", "sleep"])
        #expect(policy.shouldStayQuiet(in: QuietSceneSnapshot(activeFocusModes: ["work"])))
        #expect(policy.shouldStayQuiet(in: QuietSceneSnapshot(activeFocusModes: ["personal"])) == false)
    }

    /// The failure that matters: a signal we cannot read must never be treated
    /// as "the scene is active". Swallowing an approval because a JSON file was
    /// missing would look identical to the agent hanging.
    @Test("An unreadable signal never suppresses")
    func unavailableNeverSuppresses() {
        let policy = QuietScenePolicy(
            quietFocusModes: ["work"],
            quietWhenScreenObscured: true,
            quietWhenScreenCaptured: true
        )
        #expect(policy.shouldStayQuiet(in: .unknown) == false)
    }

    @Test("A locked screen suppresses only when asked")
    func lockedScreen() {
        let locked = QuietSceneSnapshot(screenIsObscured: .active)
        #expect(QuietScenePolicy(quietWhenScreenObscured: true).shouldStayQuiet(in: locked))
        #expect(QuietScenePolicy(quietWhenScreenObscured: false).shouldStayQuiet(in: locked) == false)
    }

    @Test("A shared screen suppresses only when asked")
    func sharedScreen() {
        let shared = QuietSceneSnapshot(screenIsBeingShared: .active)
        #expect(QuietScenePolicy(quietWhenScreenCaptured: true).shouldStayQuiet(in: shared))
        #expect(QuietScenePolicy(quietWhenScreenCaptured: false).shouldStayQuiet(in: shared) == false)
    }
}

@Suite("Focus database reading")
struct FocusModeReaderTests {
    private func write(_ json: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "focus-\(UUID().uuidString).json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test("Reads the shape macOS writes today")
    func readsNestedAssertions() throws {
        let url = try write("""
        {"data":[{"storeAssertionRecords":[{"assertionDetails":
        {"assertionDetailsModeIdentifier":"com.apple.donotdisturb.mode.default"}}]}]}
        """)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(FocusModeReader.activeModes(inAssertionsAt: url) == ["doNotDisturb"])
    }

    /// The reason the parser walks the tree instead of following one key path:
    /// Apple has reshuffled this file before and will again.
    @Test("Survives the identifier moving to a different depth")
    func survivesReshuffle() throws {
        let url = try write("""
        {"somethingNew":{"records":[{"deeper":{"modeIdentifier":"com.apple.focus.work"}}]}}
        """)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(FocusModeReader.activeModes(inAssertionsAt: url) == ["work"])
    }

    @Test("An unknown identifier is ignored, not guessed at")
    func ignoresUnknownModes() throws {
        let url = try write("""
        {"records":[{"assertionDetailsModeIdentifier":"com.apple.focus.driving"}]}
        """)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(FocusModeReader.activeModes(inAssertionsAt: url) == [])
    }

    @Test("A missing database reads as unknown, not as no focus")
    func missingFileIsUnknown() {
        let url = URL(filePath: "/nonexistent/\(UUID().uuidString).json")
        #expect(FocusModeReader.activeModes(inAssertionsAt: url) == nil)
    }

    @Test("Malformed JSON reads as unknown")
    func malformedIsUnknown() throws {
        let url = try write("not json at all")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(FocusModeReader.activeModes(inAssertionsAt: url) == nil)
    }
}

@Suite("Screen sharing detection")
struct ScreenSharingAppsTests {
    @Test(arguments: ["com.microsoft.teams", "com.microsoft.teams2", "com.cisco.webexmeetingsapp",
                      "com.loom.desktop", "com.apple.QuickTimePlayerX", "com.apple.ScreenSharing",
                      "com.tinyspeck.slackmacgap.helper.screensharing", "com.obsproject.obs-studio"])
    func openAppIsNotSharing(identifier: String) {
        #expect(ScreenSharingApps.isSharing(runningBundleIdentifiers: [identifier]) == false)
    }

    @Test("macOS capture is detected")
    func macOSCapture() {
        #expect(ScreenSharingApps.isSharing(runningBundleIdentifiers: ["com.apple.screencaptureui"]))
    }

    @Test("A known meeting app counts as sharing")
    func detectsKnownApp() {
        #expect(ScreenSharingApps.isSharing(runningBundleIdentifiers: ["us.zoom.CptHost", "com.apple.finder"]))
    }

    @Test("Zoom open without sharing does not count")
    func ignoresIdleZoom() {
        #expect(ScreenSharingApps.isSharing(runningBundleIdentifiers: ["us.zoom.xos", "us.zoom.caphost"]) == false)
    }

    @Test("An ordinary set of apps does not")
    func ignoresOtherApps() {
        #expect(ScreenSharingApps.isSharing(runningBundleIdentifiers: ["com.apple.finder"]) == false)
        #expect(ScreenSharingApps.isSharing(runningBundleIdentifiers: []) == false)
    }
}

/// 画面共有中に机を隠すかどうか。読めなかった信号で画面を変えないことが要件。
struct DesktopCoverTests {
    @Test
    func theDesktopIsHiddenOnlyWhileSharingIsCertain() {
        let sharing = QuietSceneSnapshot(screenIsBeingShared: .active)
        #expect(DesktopCover.shouldCover(scene: sharing, isEnabled: true))
        #expect(DesktopCover.shouldCover(scene: sharing, isEnabled: false) == false)
    }

    /// 共有していないのに机が消えるのは事故でしかない。読めなかったときは
    /// 隠さない——「見に行けなかった」を「起きている」として扱わない。
    @Test
    func anUnreadableSignalNeverHidesTheDesktop() {
        #expect(DesktopCover.shouldCover(
            scene: QuietSceneSnapshot(screenIsBeingShared: .unavailable), isEnabled: true) == false)
        #expect(DesktopCover.shouldCover(
            scene: QuietSceneSnapshot(screenIsBeingShared: .inactive), isEnabled: true) == false)
    }
}

@Suite("OBS activity logs")
struct OBSActivityReaderTests {
    @Test(arguments: [
        ("18:40:38.614: ==== Recording Start ======", true),
        ("==== Recording Start ====\n==== Recording Stop ====", false),
        ("==== Streaming Start ====\n==== Recording Stop ====", true),
        ("==== Streaming Start ====\n==== Streaming Stop ====", false),
        ("", false)
    ])
    func readsLastTransition(log: String, expected: Bool) {
        #expect(OBSActivityReader.isActive(log: log) == expected)
    }

    @Test("Only the newest txt log is read")
    func newestLog() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let older = directory.appending(path: "older.txt")
        try "==== Recording Start".write(to: older, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: older.path)
        try "==== Recording Stop".write(to: directory.appending(path: "newer.txt"), atomically: true, encoding: .utf8)
        try "==== Recording Start".write(to: directory.appending(path: "ignored.json"), atomically: true, encoding: .utf8)
        #expect(OBSActivityReader.isActive(inLogsAt: directory) == false)
        #expect(OBSActivityReader.isActive(inLogsAt: directory.appending(path: "missing")) == false)
    }
}
