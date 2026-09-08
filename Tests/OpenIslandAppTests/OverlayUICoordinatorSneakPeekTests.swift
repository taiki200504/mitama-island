import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// `OverlayUICoordinator.presentSneakPeek(_:)`'s own bookkeeping: expiry
/// timers, the one pending `timerDone` slot, and the guard against a
/// candidate that's already dead on arrival. `sneakPeekDurationProvider` lets
/// these run on second-scale windows instead of the real 1.2–4s the
/// production policy hands back — still real wall-clock waits, so margins
/// here are generous and checks poll rather than assume a fixed delay lands
/// exactly on schedule under a busy test run.
@MainActor
@Suite("Overlay sneak peek presentation")
struct OverlayUICoordinatorSneakPeekTests {
    private func peek(_ kind: IslandSneakPeekKind, text: String = "x", until: Date) -> IslandSneakPeek {
        IslandSneakPeek(kind: kind, text: text, icon: "circle", until: until)
    }

    private func poll(
        timeout: Duration = .seconds(3),
        until condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test("A candidate that's already past its own `until` is ignored outright")
    func expiredCandidateIsIgnored() {
        let coordinator = OverlayUICoordinator()
        coordinator.presentSneakPeek(peek(.shelf, until: Date.now.addingTimeInterval(-1)))
        #expect(coordinator.sneakPeek == nil)
    }

    @Test("An expired candidate does not even get to bump a still-showing lower one")
    func expiredCandidateDoesNotReplaceWhatIsShowing() {
        let coordinator = OverlayUICoordinator()
        let showing = peek(.hudGauge, until: Date.now.addingTimeInterval(5))
        coordinator.presentSneakPeek(showing)
        coordinator.presentSneakPeek(peek(.shelf, until: Date.now.addingTimeInterval(-1)))
        #expect(coordinator.sneakPeek == showing)
    }

    @Test("A higher-priority peek replacing a shorter one leaves no old expiry task able to clobber it")
    func supersededPeekDoesNotExpireLater() async throws {
        let coordinator = OverlayUICoordinator()
        let now = Date.now
        coordinator.presentSneakPeek(peek(.shelf, until: now.addingTimeInterval(0.2)))
        coordinator.presentSneakPeek(peek(.hudGauge, until: now.addingTimeInterval(3)))

        // Past the .shelf peek's own (superseded) deadline, but nowhere near
        // the still-active .hudGauge one — if the old .shelf expiry task had
        // survived the replacement, it would have cleared this out by now.
        try await Task.sleep(for: .milliseconds(700))

        #expect(coordinator.sneakPeek?.kind == .hudGauge)
    }

    @Test("A pending timerDone re-appears with a freshly computed until, not the stale one it lost with", .enabled(if: !TestEnvironment.isCI, "wall-clock expiry; CI runners stall for seconds"))
    func pendingTimerDoneGetsAFreshUntil() async throws {
        let coordinator = OverlayUICoordinator()
        coordinator.sneakPeekDurationProvider = { kind in kind == .timerDone ? 2.0 : 0.2 }
        let now = Date.now

        // timerDone arrives first with a long window...
        coordinator.presentSneakPeek(peek(.timerDone, text: "done", until: now.addingTimeInterval(30)))
        // ...then a higher kind interrupts it almost immediately.
        coordinator.presentSneakPeek(peek(.hudGauge, until: now.addingTimeInterval(0.2)))
        #expect(coordinator.sneakPeek?.kind == .hudGauge)

        try await poll { coordinator.sneakPeek?.kind == .timerDone }

        #expect(coordinator.sneakPeek?.kind == .timerDone)
        let remaining = coordinator.sneakPeek?.until.timeIntervalSinceNow ?? -1
        // Close to its own fresh 2s window, not the 30s it originally lost
        // with, and not already expired either.
        #expect(remaining > 0.5)
        #expect(remaining < 5)
    }

    @Test("A pending timerDone that never gets bumped again simply expires on its own", .enabled(if: !TestEnvironment.isCI, "wall-clock expiry; CI runners stall for seconds"))
    func pendingTimerDoneStillExpiresEventually() async throws {
        let coordinator = OverlayUICoordinator()
        coordinator.sneakPeekDurationProvider = { _ in 0.2 }
        let now = Date.now

        coordinator.presentSneakPeek(peek(.timerDone, text: "done", until: now.addingTimeInterval(30)))
        coordinator.presentSneakPeek(peek(.hudGauge, until: now.addingTimeInterval(0.2)))

        // Long enough for the interrupting peek to expire, the pending
        // timerDone to re-show with its own fresh (short) window, and that
        // window to run out too.
        try await poll(timeout: .seconds(4)) { coordinator.sneakPeek == nil }

        #expect(coordinator.sneakPeek == nil)
    }

    @Test("updateSneakPeek mutates the showing peek in place, leaving `until` untouched")
    func updateSneakPeekMutatesInPlace() {
        let coordinator = OverlayUICoordinator()
        let until = Date.now.addingTimeInterval(5)
        coordinator.presentSneakPeek(peek(.lockScan, text: "Taiki", until: until))

        coordinator.updateSneakPeek(where: .lockScan) { current in
            IslandSneakPeek(kind: current.kind, text: current.text, icon: "face.smiling", gauge: current.gauge, until: current.until)
        }

        #expect(coordinator.sneakPeek?.icon == "face.smiling")
        #expect(coordinator.sneakPeek?.text == "Taiki")
        #expect(coordinator.sneakPeek?.until == until)
    }

    @Test("updateSneakPeek does nothing when the showing peek is a different kind")
    func updateSneakPeekIsNoOpForWrongKind() {
        let coordinator = OverlayUICoordinator()
        let showing = peek(.hudGauge, until: Date.now.addingTimeInterval(5))
        coordinator.presentSneakPeek(showing)

        coordinator.updateSneakPeek(where: .lockScan) { current in
            IslandSneakPeek(kind: current.kind, text: current.text, icon: "face.smiling", gauge: current.gauge, until: current.until)
        }

        #expect(coordinator.sneakPeek == showing)
    }

    @Test("updateSneakPeek does nothing when nothing is showing")
    func updateSneakPeekIsNoOpWhenNothingShowing() {
        let coordinator = OverlayUICoordinator()

        coordinator.updateSneakPeek(where: .lockScan) { current in
            IslandSneakPeek(kind: current.kind, text: current.text, icon: "face.smiling", gauge: current.gauge, until: current.until)
        }

        #expect(coordinator.sneakPeek == nil)
    }

    @Test("A peek updated in place still expires on schedule despite its content changing")
    func updatedSneakPeekStillExpires() async throws {
        let coordinator = OverlayUICoordinator()
        let until = Date.now.addingTimeInterval(0.3)
        coordinator.presentSneakPeek(peek(.lockScan, text: "Taiki", until: until))

        coordinator.updateSneakPeek(where: .lockScan) { current in
            IslandSneakPeek(kind: current.kind, text: current.text, icon: "face.smiling", gauge: current.gauge, until: current.until)
        }

        try await poll(timeout: .seconds(2)) { coordinator.sneakPeek == nil }

        #expect(coordinator.sneakPeek == nil)
    }
}
