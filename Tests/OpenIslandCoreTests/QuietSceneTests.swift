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
    @Test("A known meeting app counts as sharing")
    func detectsKnownApp() {
        #expect(ScreenSharingApps.isSharing(runningBundleIdentifiers: ["us.zoom.xos", "com.apple.finder"]))
    }

    @Test("An ordinary set of apps does not")
    func ignoresOtherApps() {
        #expect(ScreenSharingApps.isSharing(runningBundleIdentifiers: ["com.apple.finder"]) == false)
        #expect(ScreenSharingApps.isSharing(runningBundleIdentifiers: []) == false)
    }
}
