import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Focus timer state machine")
struct FocusTimerTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Start / pause / resume / reset

    @Test("Starting a countdown begins running with the full duration")
    func startCountdown() {
        let state = FocusTimerReducer.reduce(.idle, .start(.countdown(300)), now: epoch)
        #expect(state.phase == .running(endsAt: epoch.addingTimeInterval(300)))
        #expect(state.currentPhaseDuration == 300)
        #expect(state.cycle == 0)
        #expect(state.isRest == false)
    }

    @Test("Pausing a running timer freezes the remaining time")
    func pauseFreezesRemaining() {
        let started = FocusTimerReducer.reduce(.idle, .start(.countdown(300)), now: epoch)
        let paused = FocusTimerReducer.reduce(started, .pause, now: epoch.addingTimeInterval(100))
        #expect(paused.phase == .paused(remaining: 200))
    }

    @Test("Resuming recomputes endsAt from the paused remainder, not the original one")
    func resumeRecomputesEndsAt() {
        let started = FocusTimerReducer.reduce(.idle, .start(.countdown(300)), now: epoch)
        let paused = FocusTimerReducer.reduce(started, .pause, now: epoch.addingTimeInterval(100))
        let resumedAt = epoch.addingTimeInterval(9_000)
        let resumed = FocusTimerReducer.reduce(paused, .resume, now: resumedAt)
        #expect(resumed.phase == .running(endsAt: resumedAt.addingTimeInterval(200)))
    }

    @Test("Pause and resume are no-ops from the wrong phase")
    func pauseResumeGuardWrongPhase() {
        #expect(FocusTimerReducer.reduce(.idle, .pause, now: epoch) == .idle)
        #expect(FocusTimerReducer.reduce(.idle, .resume, now: epoch) == .idle)
    }

    @Test("Reset always returns to idle, regardless of phase")
    func resetReturnsToIdle() {
        let started = FocusTimerReducer.reduce(.idle, .start(.pomodoro()), now: epoch)
        let reset = FocusTimerReducer.reduce(started, .reset, now: epoch.addingTimeInterval(50))
        #expect(reset == .idle)
    }

    // MARK: - Tick / finish

    @Test("Tick before endsAt is a no-op")
    func tickBeforeEndsAtIsNoOp() {
        let started = FocusTimerReducer.reduce(.idle, .start(.countdown(300)), now: epoch)
        let ticked = FocusTimerReducer.reduce(started, .tick, now: epoch.addingTimeInterval(299))
        #expect(ticked == started)
    }

    @Test("Tick at or after endsAt finishes the phase")
    func tickAtEndsAtFinishes() {
        let started = FocusTimerReducer.reduce(.idle, .start(.countdown(300)), now: epoch)
        let endsAt = epoch.addingTimeInterval(300)
        let finished = FocusTimerReducer.reduce(started, .tick, now: endsAt)
        #expect(finished.phase == .finished(at: endsAt))
    }

    @Test("Advance on a plain countdown goes idle — nothing left to advance to")
    func countdownAdvanceGoesIdle() {
        let started = FocusTimerReducer.reduce(.idle, .start(.countdown(60)), now: epoch)
        let finished = FocusTimerReducer.reduce(started, .tick, now: epoch.addingTimeInterval(60))
        let advanced = FocusTimerReducer.reduce(finished, .advance, now: epoch.addingTimeInterval(60))
        #expect(advanced == .idle)
    }

    @Test("Advance is a no-op unless the phase is finished")
    func advanceGuardsAgainstNonFinished() {
        let started = FocusTimerReducer.reduce(.idle, .start(.countdown(60)), now: epoch)
        let advanced = FocusTimerReducer.reduce(started, .advance, now: epoch.addingTimeInterval(1))
        #expect(advanced == started)
    }

    // MARK: - Pomodoro

    @Test("Pomodoro work finishing advances into a short rest")
    func pomodoroWorkToShortRest() {
        let mode = FocusTimerMode.pomodoro(work: 1_500, short: 300, long: 900, every: 4)
        let started = FocusTimerReducer.reduce(.idle, .start(mode), now: epoch)
        let finished = FocusTimerReducer.reduce(started, .tick, now: epoch.addingTimeInterval(1_500))
        let advanced = FocusTimerReducer.reduce(finished, .advance, now: epoch.addingTimeInterval(1_500))

        #expect(advanced.isRest == true)
        #expect(advanced.cycle == 1)
        #expect(advanced.currentPhaseDuration == 300)
    }

    @Test("Pomodoro rest finishing advances back into work")
    func pomodoroRestToWork() {
        let mode = FocusTimerMode.pomodoro(work: 1_500, short: 300, long: 900, every: 4)
        var state = FocusTimerReducer.reduce(.idle, .start(mode), now: epoch)
        state = FocusTimerReducer.reduce(state, .tick, now: epoch.addingTimeInterval(1_500))
        state = FocusTimerReducer.reduce(state, .advance, now: epoch.addingTimeInterval(1_500))
        state = FocusTimerReducer.reduce(state, .tick, now: epoch.addingTimeInterval(1_800))
        let backToWork = FocusTimerReducer.reduce(state, .advance, now: epoch.addingTimeInterval(1_800))

        #expect(backToWork.isRest == false)
        #expect(backToWork.cycle == 1)
        #expect(backToWork.currentPhaseDuration == 1_500)
    }

    @Test("The 4th work session is followed by a long rest, not a short one")
    func fourthPomodoroWorkGetsLongRest() {
        let mode = FocusTimerMode.pomodoro(work: 60, short: 10, long: 100, every: 4)
        var state = FocusTimerReducer.reduce(.idle, .start(mode), now: epoch)
        var now = epoch

        // Cycle through three full work→rest pairs.
        for _ in 0..<3 {
            now = now.addingTimeInterval(60)
            state = FocusTimerReducer.reduce(state, .tick, now: now)
            state = FocusTimerReducer.reduce(state, .advance, now: now)
            #expect(state.currentPhaseDuration == 10, "expected a short rest before the 4th work session")
            now = now.addingTimeInterval(10)
            state = FocusTimerReducer.reduce(state, .tick, now: now)
            state = FocusTimerReducer.reduce(state, .advance, now: now)
        }

        // The 4th work session finishes here.
        now = now.addingTimeInterval(60)
        state = FocusTimerReducer.reduce(state, .tick, now: now)
        let afterFourth = FocusTimerReducer.reduce(state, .advance, now: now)

        #expect(afterFourth.cycle == 4)
        #expect(afterFourth.isRest == true)
        #expect(afterFourth.currentPhaseDuration == 100, "the rest after the 4th work session should be long")
    }

    // MARK: - Eye break

    @Test("Eye break cycles 20 minutes of work into 20 seconds of rest and back")
    func eyeBreakCycle() {
        let mode = FocusTimerMode.eyeBreak(work: 20 * 60, rest: 20)
        var state = FocusTimerReducer.reduce(.idle, .start(mode), now: epoch)
        #expect(state.currentPhaseDuration == 20 * 60)

        var now = epoch.addingTimeInterval(20 * 60)
        state = FocusTimerReducer.reduce(state, .tick, now: now)
        state = FocusTimerReducer.reduce(state, .advance, now: now)
        #expect(state.isRest == true)
        #expect(state.currentPhaseDuration == 20)
        #expect(state.cycle == 1)

        now = now.addingTimeInterval(20)
        state = FocusTimerReducer.reduce(state, .tick, now: now)
        state = FocusTimerReducer.reduce(state, .advance, now: now)
        #expect(state.isRest == false)
        #expect(state.currentPhaseDuration == 20 * 60)
        #expect(state.cycle == 1)
    }

    // MARK: - Pause → resume → endsAt recomputed (dedicated eye-break variant)

    @Test("Pausing mid-rest and resuming later still ends exactly `remaining` after resume")
    func pauseResumeDuringRestRecomputesEndsAt() {
        let mode = FocusTimerMode.eyeBreak(work: 60, rest: 20)
        var state = FocusTimerReducer.reduce(.idle, .start(mode), now: epoch)
        state = FocusTimerReducer.reduce(state, .tick, now: epoch.addingTimeInterval(60))
        state = FocusTimerReducer.reduce(state, .advance, now: epoch.addingTimeInterval(60))

        let pauseAt = epoch.addingTimeInterval(65)
        let paused = FocusTimerReducer.reduce(state, .pause, now: pauseAt)
        #expect(paused.phase == .paused(remaining: 15))

        let resumeAt = epoch.addingTimeInterval(500)
        let resumed = FocusTimerReducer.reduce(paused, .resume, now: resumeAt)
        #expect(resumed.phase == .running(endsAt: resumeAt.addingTimeInterval(15)))
    }

    // MARK: - Clock moving backwards

    @Test("A clock that jumps backwards never produces a negative remaining or progress")
    func backwardsClockClamps() {
        let started = FocusTimerReducer.reduce(.idle, .start(.countdown(60)), now: epoch)
        let before = epoch.addingTimeInterval(-1_000)

        #expect(started.remaining(at: before) >= 0)
        #expect(started.progress(at: before) >= 0)
        #expect(started.progress(at: before) <= 1)
    }

    @Test("Tick never fires early even if the clock jumped backwards")
    func backwardsClockNeverFinishesEarly() {
        let started = FocusTimerReducer.reduce(.idle, .start(.countdown(60)), now: epoch)
        let ticked = FocusTimerReducer.reduce(started, .tick, now: epoch.addingTimeInterval(-1_000))
        #expect(ticked == started)
    }

    // MARK: - remaining(at:) / progress(at:)

    @Test("remaining(at:) reflects the wall-clock gap to endsAt while running")
    func remainingWhileRunning() {
        let started = FocusTimerReducer.reduce(.idle, .start(.countdown(120)), now: epoch)
        #expect(started.remaining(at: epoch.addingTimeInterval(50)) == 70)
    }

    @Test("progress(at:) is 0 at the start and 1 once the phase is spent")
    func progressBoundaries() {
        let started = FocusTimerReducer.reduce(.idle, .start(.countdown(100)), now: epoch)
        #expect(started.progress(at: epoch) == 0)
        #expect(started.progress(at: epoch.addingTimeInterval(100)) == 1)
        #expect(started.progress(at: epoch.addingTimeInterval(50)) == 0.5)
    }

    @Test("Idle has zero progress and finished has full progress")
    func progressAtRest() {
        #expect(FocusTimerState.idle.progress(at: epoch) == 0)

        let started = FocusTimerReducer.reduce(.idle, .start(.countdown(30)), now: epoch)
        let finished = FocusTimerReducer.reduce(started, .tick, now: epoch.addingTimeInterval(30))
        #expect(finished.progress(at: epoch.addingTimeInterval(30)) == 1)
    }

    // MARK: - Snapshot minutes rounding

    @Test("Snapshot rounds 59 seconds remaining up to 1 minute")
    func snapshotRounds59SecondsUpToOneMinute() {
        let started = FocusTimerReducer.reduce(.idle, .start(.countdown(59)), now: epoch)
        #expect(started.snapshot(at: epoch)?.remainingMinutes == 1)
    }

    @Test("Snapshot rounds 61 seconds remaining up to 2 minutes")
    func snapshotRounds61SecondsUpToTwoMinutes() {
        let started = FocusTimerReducer.reduce(.idle, .start(.countdown(61)), now: epoch)
        #expect(started.snapshot(at: epoch)?.remainingMinutes == 2)
    }

    @Test("Snapshot is nil while idle or finished")
    func snapshotNilWhenIdleOrFinished() {
        #expect(FocusTimerState.idle.snapshot(at: epoch) == nil)

        let started = FocusTimerReducer.reduce(.idle, .start(.countdown(30)), now: epoch)
        let finished = FocusTimerReducer.reduce(started, .tick, now: epoch.addingTimeInterval(30))
        #expect(finished.snapshot(at: epoch.addingTimeInterval(30)) == nil)
    }

    @Test("Snapshot label follows work/rest, and a plain countdown always reads FOCUS")
    func snapshotLabels() {
        let countdown = FocusTimerReducer.reduce(.idle, .start(.countdown(60)), now: epoch)
        #expect(countdown.snapshot(at: epoch)?.label == "FOCUS")

        let mode = FocusTimerMode.pomodoro(work: 60, short: 10, long: 100, every: 4)
        var pomodoro = FocusTimerReducer.reduce(.idle, .start(mode), now: epoch)
        #expect(pomodoro.snapshot(at: epoch)?.label == "WORK")

        pomodoro = FocusTimerReducer.reduce(pomodoro, .tick, now: epoch.addingTimeInterval(60))
        pomodoro = FocusTimerReducer.reduce(pomodoro, .advance, now: epoch.addingTimeInterval(60))
        #expect(pomodoro.snapshot(at: epoch.addingTimeInterval(60))?.label == "REST")
    }
}
