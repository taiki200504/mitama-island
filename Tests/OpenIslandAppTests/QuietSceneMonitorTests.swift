import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

@Suite("Quiet scene monitor", .serialized)
@MainActor
struct QuietSceneMonitorTests {
    private func monitor(
        focusJSON: String? = nil,
        running: Set<String> = [],
        locked: Bool = false
    ) throws -> QuietSceneMonitor {
        var url = URL(filePath: "/nonexistent/\(UUID().uuidString).json")
        if let focusJSON {
            url = FileManager.default.temporaryDirectory
                .appending(path: "focus-\(UUID().uuidString).json")
            try focusJSON.write(to: url, atomically: true, encoding: .utf8)
        }
        return QuietSceneMonitor(
            assertionsURL: url,
            runningBundleIdentifiers: { running },
            screenIsLocked: { locked }
        )
    }

    @Test("Reports the focus mode macOS has on")
    func readsFocus() throws {
        let monitor = try monitor(
            focusJSON: #"{"a":{"assertionDetailsModeIdentifier":"com.apple.focus.work"}}"#
        )
        monitor.refresh()
        #expect(monitor.snapshot.activeFocusModes == ["work"])
        #expect(monitor.focusDetectionIsAvailable)
    }

    /// The settings pane leans on this to swap the switch for an explanation
    /// rather than leaving a control that can never fire.
    @Test("An unreadable database is reported as unavailable")
    func unreadableFocus() throws {
        let monitor = try monitor()
        monitor.refresh()
        #expect(monitor.focusDetectionIsAvailable == false)
    }

    @Test("A locked screen shows up in the snapshot")
    func readsLock() throws {
        let monitor = try monitor(locked: true)
        monitor.refresh()
        #expect(monitor.snapshot.screenIsObscured == .active)
    }

    @Test("A running meeting app shows up as sharing")
    func readsSharing() throws {
        let monitor = try monitor(running: ["us.zoom.xos"])
        monitor.refresh()
        #expect(monitor.snapshot.screenIsBeingShared == .active)
    }

    @Test("Settings drive the decision")
    func honoursSettings() throws {
        let defaults = UserDefaults(suiteName: "quiet-scene-\(UUID().uuidString)")!
        let behaviour = BehaviourSettings(store: PreferenceStore(suite: defaults))
        let monitor = try monitor(locked: true)
        monitor.refresh()

        behaviour.quietWhenScreenObscured = false
        #expect(monitor.shouldStayQuiet(under: behaviour) == false)

        behaviour.quietWhenScreenObscured = true
        #expect(monitor.shouldStayQuiet(under: behaviour))
    }
}

@Suite("Quiet scene defaults")
@MainActor
struct QuietSceneDefaultsTests {
    private func makeBehaviour() -> BehaviourSettings {
        let defaults = UserDefaults(suiteName: "quiet-defaults-\(UUID().uuidString)")!
        return BehaviourSettings(store: PreferenceStore(suite: defaults))
    }

    /// The bug this pins: screen-share detection is inferred from a recording
    /// or meeting app merely being open. Shipped on by default, QuickTime
    /// sitting in the Dock silently swallowed every approval card. A signal
    /// this coarse has to be opted into.
    @Test("Screen-share silencing is off until asked for")
    func screenCaptureIsOptIn() {
        #expect(makeBehaviour().quietWhenScreenCaptured == false)
    }

    /// A locked screen is reported exactly by macOS, and nothing is visible
    /// there anyway, so this one may default on.
    @Test("Screen-lock silencing is on by default")
    func screenLockIsDefaultOn() {
        #expect(makeBehaviour().quietWhenScreenObscured)
    }

    @Test("No focus mode silences until one is chosen")
    func focusIsOptIn() {
        #expect(makeBehaviour().quietFocusModes.isEmpty)
    }

    /// Whatever the machine happens to be doing, an untouched install must let
    /// notifications through.
    @Test("A fresh install suppresses nothing")
    func freshInstallIsSilent() throws {
        let behaviour = makeBehaviour()
        let monitor = QuietSceneMonitor(
            assertionsURL: URL(filePath: "/nonexistent/\(UUID().uuidString).json"),
            runningBundleIdentifiers: { ["us.zoom.xos", "com.apple.QuickTimePlayerX"] },
            screenIsLocked: { false }
        )
        monitor.refresh()
        #expect(monitor.shouldStayQuiet(under: behaviour) == false)
    }
}
