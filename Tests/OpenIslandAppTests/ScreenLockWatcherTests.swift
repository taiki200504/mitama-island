import Foundation
import Testing
@testable import OpenIslandApp

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

    @Test("Locking flips isLocked and fires onLocked")
    func lockingFlipsState() {
        let (watcher, center) = makeWatcher()
        var lockedCount = 0
        watcher.onLocked = { lockedCount += 1 }

        center.post(name: Self.lockedName, object: nil)

        #expect(watcher.isLocked)
        #expect(lockedCount == 1)
    }

    @Test("Unlocking after a lock flips isLocked back and fires onUnlocked once")
    func unlockingFiresOnce() {
        let (watcher, center) = makeWatcher()
        var unlockedCount = 0
        watcher.onUnlocked = { unlockedCount += 1 }

        center.post(name: Self.lockedName, object: nil)
        center.post(name: Self.unlockedName, object: nil)

        #expect(!watcher.isLocked)
        #expect(unlockedCount == 1)
    }

    @Test("A stray unlock notification without a prior lock fires nothing")
    func strayUnlockIsIgnored() {
        let (watcher, center) = makeWatcher()
        var unlockedCount = 0
        watcher.onUnlocked = { unlockedCount += 1 }

        center.post(name: Self.unlockedName, object: nil)

        #expect(!watcher.isLocked)
        #expect(unlockedCount == 0)
    }

    @Test("A second lock/unlock cycle fires onUnlocked exactly once again")
    func repeatedCycleFiresOncePerUnlock() {
        let (watcher, center) = makeWatcher()
        var unlockedCount = 0
        watcher.onUnlocked = { unlockedCount += 1 }

        center.post(name: Self.lockedName, object: nil)
        center.post(name: Self.unlockedName, object: nil)
        center.post(name: Self.lockedName, object: nil)
        center.post(name: Self.unlockedName, object: nil)

        #expect(unlockedCount == 2)
    }

    @Test("start() called twice does not double-register observers")
    func startIsIdempotent() {
        let (watcher, center) = makeWatcher()
        watcher.start()
        var unlockedCount = 0
        watcher.onUnlocked = { unlockedCount += 1 }

        center.post(name: Self.lockedName, object: nil)
        center.post(name: Self.unlockedName, object: nil)

        #expect(unlockedCount == 1)
    }

    @Test("stop() removes observers so further notifications do nothing")
    func stopRemovesObservers() {
        let (watcher, center) = makeWatcher()
        watcher.stop()
        var unlockedCount = 0
        watcher.onUnlocked = { unlockedCount += 1 }

        center.post(name: Self.lockedName, object: nil)
        center.post(name: Self.unlockedName, object: nil)

        #expect(!watcher.isLocked)
        #expect(unlockedCount == 0)
    }
}
