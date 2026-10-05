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
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        coordinator.sneakPeekNow = { now }
        // The superseded .shelf deadline (0.2s out) is reported as already
        // passed; the .hudGauge one (3s out) never arrives. No wall-clock
        // wait, so a stalled CI runner can't expire the gauge by accident.
        let cutoff = ContinuousClock.now.advanced(by: .seconds(1.5))
        let released = ExpiredDeadlineCounter()
        coordinator.sneakPeekExpiryWait = { deadline in
            if deadline < cutoff {
                await released.increment()
                return
            }
            try await Task.sleep(for: .seconds(3600))
        }
        coordinator.presentSneakPeek(peek(.shelf, until: now.addingTimeInterval(0.2)))
        coordinator.presentSneakPeek(peek(.hudGauge, until: now.addingTimeInterval(3)))

        while await released.count() == 0 { await Task.yield() }
        // Give a surviving .shelf task every chance to clear the gauge.
        try await poll(timeout: .milliseconds(300)) { coordinator.sneakPeek?.kind != .hudGauge }

        #expect(coordinator.sneakPeek?.kind == .hudGauge)
    }

    @Test("A pending timerDone re-appears with a freshly computed until, not the stale one it lost with")
    func pendingTimerDoneGetsAFreshUntil() async throws {
        let coordinator = OverlayUICoordinator()
        let gate = PeekExpiryGate()
        coordinator.sneakPeekExpiryWait = { deadline in await gate.wait(deadline) }
        coordinator.sneakPeekDurationProvider = { kind in kind == .timerDone ? 2.0 : 0.2 }
        var now = Date(timeIntervalSince1970: 1_000_000_000)
        coordinator.sneakPeekNow = { now }
        let originalUntil = now.addingTimeInterval(30)
        coordinator.presentSneakPeek(peek(.timerDone, text: "done", until: originalUntil))
        coordinator.presentSneakPeek(peek(.hudGauge, until: now.addingTimeInterval(0.2)))
        #expect(coordinator.sneakPeek?.kind == .hudGauge)
        while !(await gate.isWaiting()) { await Task.yield() }

        // The original timer window is now stale. Releasing the blocker
        // must give the queued timer exactly its own duration from this now.
        now = now.addingTimeInterval(40)
        let expectedUntil = now.addingTimeInterval(2)
        await gate.expire()
        try await poll { coordinator.sneakPeek?.kind == .timerDone }
        #expect(coordinator.sneakPeek?.until == expectedUntil)
        #expect(coordinator.sneakPeek?.until != originalUntil)
        #expect(coordinator.sneakPeek?.text == "done")
        while !(await gate.isWaiting()) { await Task.yield() }
        await gate.expire()
        try await poll { coordinator.sneakPeek == nil }
        #expect(coordinator.sneakPeek == nil)
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

    @Test("A peek updated in place keeps its original expiry reservation despite content changing")
    func updatedSneakPeekStillExpires() async throws {
        let coordinator = OverlayUICoordinator()
        let gate = PeekExpiryGate()
        coordinator.sneakPeekExpiryWait = { deadline in await gate.wait(deadline) }
        let before = ContinuousClock.now
        let until = Date.now.addingTimeInterval(30)
        coordinator.presentSneakPeek(peek(.lockScan, text: "Taiki", until: until))
        while !(await gate.isWaiting()) { await Task.yield() }
        let reservation = await gate.deadlines()
        #expect(reservation.count == 1)
        let deadline = try #require(reservation.first)
        #expect(deadline >= before.advanced(by: .seconds(29)))
        #expect(deadline <= before.advanced(by: .seconds(31)))

        coordinator.updateSneakPeek(where: .lockScan) { current in
            IslandSneakPeek(kind: current.kind, text: current.text, icon: "face.smiling", gauge: current.gauge, until: current.until)
        }
        #expect(coordinator.sneakPeek?.until == until)
        #expect(coordinator.sneakPeek?.icon == "face.smiling")
        #expect(await gate.deadlines() == reservation)
        await gate.expire()
        try await poll { coordinator.sneakPeek == nil }

        #expect(coordinator.sneakPeek == nil)
    }
}

private actor ExpiredDeadlineCounter {
    private var value = 0
    func increment() { value += 1 }
    func count() -> Int { value }
}

private actor PeekExpiryGate {
    private var captured: [ContinuousClock.Instant] = []
    private var continuation: CheckedContinuation<Void, Never>?
    func wait(_ deadline: ContinuousClock.Instant) async {
        guard !Task.isCancelled else { return }
        captured.append(deadline)
        await withCheckedContinuation { continuation = $0 }
    }
    func isWaiting() -> Bool { continuation != nil }
    func deadlines() -> [ContinuousClock.Instant] { captured }
    func expire() { continuation?.resume(); continuation = nil }
}
