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
/// `queue: .main` asks the center to deliver on the main queue rather than
/// whatever thread happens to be pumping distributed notifications — that is
/// usually, but not guaranteed to be, the main thread, and `MainActor
/// .assumeIsolated` on an unguaranteed thread is a crash waiting for the one
/// time it lands elsewhere. The block still isn't statically MainActor code
/// (`addObserver`'s handler is a plain, non-isolated closure), so it hops
/// explicitly with `Task { @MainActor in … }` rather than asserting isolation
/// it cannot prove.
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
            center.addObserver(forName: Self.lockedName, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.isLocked = true
                    self?.onLocked?()
                }
            },
            center.addObserver(forName: Self.unlockedName, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
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
