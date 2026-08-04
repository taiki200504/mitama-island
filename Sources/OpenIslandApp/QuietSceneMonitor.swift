import AppKit
import CoreGraphics
import Foundation
import Observation
import OpenIslandCore
import os

/// Watches for the moments the user asked not to be interrupted in.
///
/// Nothing here is push-based across the board — Focus has no notification and
/// no API, so the Focus database is re-read on a timer. Screen sleep and wake do
/// post notifications, so those update immediately and the poll only confirms.
@MainActor
@Observable
final class QuietSceneMonitor {
    private static let logger = Logger(subsystem: "com.mitama.island", category: "quiet-scene")

    /// Long enough that re-reading a small JSON file costs nothing measurable,
    /// short enough that switching Focus on before a break takes effect by the
    /// time the next agent finishes.
    static let pollInterval: TimeInterval = 5

    private(set) var snapshot: QuietSceneSnapshot = QuietSceneSnapshot()

    private let assertionsURL: URL
    private let runningBundleIdentifiers: @MainActor () -> Set<String>
    private let screenIsLocked: () -> Bool
    private let timerBox = TimerBox()
    private var observers: [NSObjectProtocol] = []
    private var screensAreAsleep = false

    init(
        assertionsURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: FocusModeReader.defaultAssertionsPath),
        runningBundleIdentifiers: @escaping @MainActor () -> Set<String> = {
            Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        },
        screenIsLocked: @escaping () -> Bool = QuietSceneMonitor.readScreenLock
    ) {
        self.assertionsURL = assertionsURL
        self.runningBundleIdentifiers = runningBundleIdentifiers
        self.screenIsLocked = screenIsLocked
    }

    func start() {
        guard timerBox.timer == nil else { return }
        observeScreenSleep()
        refresh()
        let timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = Self.pollInterval / 2
        timerBox.timer = timer
    }

    func stop() {
        timerBox.invalidate()
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
    }

    func refresh() {
        snapshot = QuietSceneSnapshot(
            activeFocusModes: FocusModeReader.activeModes(inAssertionsAt: assertionsURL),
            screenIsObscured: (screensAreAsleep || screenIsLocked()) ? .active : .inactive,
            screenIsBeingShared: ScreenSharingApps.isSharing(
                runningBundleIdentifiers: runningBundleIdentifiers()
            ) ? .active : .inactive
        )
    }

    /// Whether the island should keep quiet under the user's current choices.
    func shouldStayQuiet(under behaviour: BehaviourSettings) -> Bool {
        QuietScenePolicy(
            quietFocusModes: Set(behaviour.quietFocusModes),
            quietWhenScreenObscured: behaviour.quietWhenScreenObscured,
            quietWhenScreenCaptured: behaviour.quietWhenScreenCaptured
        ).shouldStayQuiet(in: snapshot)
    }

    /// True when the Focus database is readable, so the settings pane can say so
    /// instead of leaving a switch that quietly never fires.
    var focusDetectionIsAvailable: Bool { snapshot.activeFocusModes != nil }

    // MARK: Screen sleep

    private func observeScreenSleep() {
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            (NSWorkspace.screensDidSleepNotification, true),
            (NSWorkspace.screensDidWakeNotification, false)
        ].map { name, asleep in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.screensAreAsleep = asleep
                    self?.refresh()
                }
            }
        }
    }

    /// The login-session dictionary is the only place macOS reports the lock
    /// screen to a normal app. It is absent in some sandboxed contexts, which we
    /// read as "not locked" rather than guessing.
    nonisolated static func readScreenLock() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        return (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}


/// Holds the poll timer outside the actor so `deinit` can stop it.
///
/// A repeating timer that outlives its owner keeps waking the app forever, and
/// `deinit` is not allowed to touch main-actor state to cancel one.
private final class TimerBox: @unchecked Sendable {
    var timer: Timer?

    deinit { timer?.invalidate() }

    func invalidate() {
        timer?.invalidate()
        timer = nil
    }
}
