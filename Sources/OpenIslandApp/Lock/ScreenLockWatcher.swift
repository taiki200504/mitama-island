import Foundation
import Observation

/// Watches for macOS locking and unlocking the screen.
///
/// Distinct from `QuietSceneMonitor`, which polls the login-session
/// dictionary every 5 seconds to answer "is the screen obscured right now"
/// for the quiet-scene gate — fine for staying quiet, but too slow for
/// something that wants the moment itself. `onLocked` exists so the caller
/// can trigger that monitor's own `refresh()` immediately rather than living
/// with its poll lag; `onUnlocked` is the greeting's cue.
///
/// `DistributedNotificationCenter` is the only place macOS posts these two
/// names to every process — there is no API that returns the lock state
/// directly. It is a subclass of `NotificationCenter`, so the default here is
/// swapped for a plain, private one in tests rather than posting onto the
/// real system-wide center.
///
/// No `queue:` is given to `addObserver` — both distributed notifications and
/// a plain center's synchronous default deliver on the thread that is
/// already pumping the run loop that registered for them, which for an
/// AppKit app is the main thread. `MainActor.assumeIsolated` below is only
/// bridging that fact across to the type system, not asking for a hop.
@MainActor
@Observable
final class ScreenLockWatcher {
    private static let lockedName = Notification.Name("com.apple.screenIsLocked")
    private static let unlockedName = Notification.Name("com.apple.screenIsUnlocked")

    private(set) var isLocked = false

    /// Fires the moment the lock notification arrives.
    var onLocked: (() -> Void)?
    /// Fires once per unlock, after `isLocked` flips back to `false`.
    var onUnlocked: (() -> Void)?

    private let center: NotificationCenter
    private var observers: [NSObjectProtocol] = []

    init(center: NotificationCenter = DistributedNotificationCenter.default()) {
        self.center = center
    }

    func start() {
        guard observers.isEmpty else { return }
        observers = [
            center.addObserver(forName: Self.lockedName, object: nil, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isLocked = true
                    self?.onLocked?()
                }
            },
            center.addObserver(forName: Self.unlockedName, object: nil, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated {
                    // Guards against a duplicate unlock notification firing the
                    // greeting twice for one actual unlock — macOS is not
                    // guaranteed to post these two names in strict alternation.
                    guard let self, self.isLocked else { return }
                    self.isLocked = false
                    self.onUnlocked?()
                }
            },
        ]
    }

    func stop() {
        observers.forEach(center.removeObserver)
        observers.removeAll()
    }

    isolated deinit {
        observers.forEach(center.removeObserver)
    }
}
