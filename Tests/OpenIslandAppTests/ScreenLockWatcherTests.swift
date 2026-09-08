import Foundation
import Testing
@testable import OpenIslandApp

/// `queue: .main` makes delivery asynchronous even when the poster is
/// already on the main thread — the observer block runs on a later turn of
/// the main queue, not inline inside `post()`. Every assertion here polls
/// rather than reading state immediately after posting.
@MainActor
struct ScreenLockWatcherTests {
    private static let lockedName = Notification.Name("com.apple.screenIsLocked")
    private static let unlockedName = Notification.Name("com.apple.screenIsUnlocked")

    private func makeWatcher() -> (ScreenLockWatcher, NotificationCenter) {
        let center = NotificationCenter()
        let watcher = ScreenLockWatcher(center: center)
        watcher.start()
        return (watcher, center)
    }

    private func poll(
        timeout: Duration = .seconds(2),
        until condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("Locking flips isLocked and fires onLocked")
    func lockingFlipsState() async throws {
        let (watcher, center) = makeWatcher()
        var lockedCount = 0
        watcher.onLocked = { lockedCount += 1 }

        center.post(name: Self.lockedName, object: nil)
        try await poll { watcher.isLocked }

        #expect(watcher.isLocked)
        #expect(lockedCount == 1)
    }

    @Test("Unlocking after a lock flips isLocked back and fires onUnlocked once")
    func unlockingFiresOnce() async throws {
        let (watcher, center) = makeWatcher()
        var unlockedCount = 0
        watcher.onUnlocked = { unlockedCount += 1 }

        center.post(name: Self.lockedName, object: nil)
        try await poll { watcher.isLocked }
        center.post(name: Self.unlockedName, object: nil)
        try await poll { unlockedCount == 1 }

        #expect(!watcher.isLocked)
        #expect(unlockedCount == 1)
    }

    @Test("A stray unlock notification without a prior lock fires nothing")
    func strayUnlockIsIgnored() async throws {
        let (watcher, center) = makeWatcher()
        var unlockedCount = 0
        watcher.onUnlocked = { unlockedCount += 1 }

        center.post(name: Self.unlockedName, object: nil)
        // Nothing to poll for that would ever become true — give the queue a
        // few turns to prove the notification really produced no effect.
        for _ in 0..<5 { await Task.yield() }

        #expect(!watcher.isLocked)
        #expect(unlockedCount == 0)
    }

    @Test("A second lock/unlock cycle fires onUnlocked exactly once again")
    func repeatedCycleFiresOncePerUnlock() async throws {
        let (watcher, center) = makeWatcher()
        var unlockedCount = 0
        watcher.onUnlocked = { unlockedCount += 1 }

        center.post(name: Self.lockedName, object: nil)
        try await poll { watcher.isLocked }
        center.post(name: Self.unlockedName, object: nil)
        try await poll { unlockedCount == 1 }
        center.post(name: Self.lockedName, object: nil)
        try await poll { watcher.isLocked }
        center.post(name: Self.unlockedName, object: nil)
        try await poll { unlockedCount == 2 }

        #expect(unlockedCount == 2)
    }

    @Test("start() called twice does not double-register observers")
    func startIsIdempotent() async throws {
        let (watcher, center) = makeWatcher()
        watcher.start()
        var unlockedCount = 0
        watcher.onUnlocked = { unlockedCount += 1 }

        center.post(name: Self.lockedName, object: nil)
        try await poll { watcher.isLocked }
        center.post(name: Self.unlockedName, object: nil)
        try await poll { unlockedCount >= 1 }

        #expect(unlockedCount == 1)
    }

    @Test("stop() removes observers so further notifications do nothing")
    func stopRemovesObservers() async throws {
        let (watcher, center) = makeWatcher()
        watcher.stop()
        var unlockedCount = 0
        watcher.onUnlocked = { unlockedCount += 1 }

        center.post(name: Self.lockedName, object: nil)
        center.post(name: Self.unlockedName, object: nil)
        for _ in 0..<5 { await Task.yield() }

        #expect(!watcher.isLocked)
        #expect(unlockedCount == 0)
    }
}
