import Foundation
import Testing
@testable import OpenIslandCore

/// A running timer only ever reaches `IslandClosedArbiter` through
/// `IslandClosedInputs.timer` — this exercises the real path from
/// `FocusTimerState` through its `snapshot(at:)` into the arbiter, rather
/// than constructing the accessory value directly the way
/// `IslandClosedArbiterTests` does for the arbiter's own priority rules.
@Suite("Focus timer feeding the closed-island arbiter")
struct FocusTimerClosedIslandIntegrationTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func waitingPeek() -> IslandPeekBand.Content {
        IslandPeekBand.Content(
            agent: "CODEX",
            subject: .session(.waitingForApproval),
            elapsed: .minutes(2),
            othersWaiting: 0
        )
    }

    @Test("A running timer becomes the accessory while a waiting agent keeps the body")
    func runningTimerIsAccessoryAlongsideWaitingBody() {
        let state = FocusTimerReducer.reduce(.idle, .start(.pomodoro()), now: epoch)
        let snapshot = state.snapshot(at: epoch.addingTimeInterval(60))
        #expect(snapshot != nil)

        let timerInput = snapshot.map {
            IslandClosedInputs.Timer(remainingMinutes: $0.remainingMinutes, label: $0.label)
        }

        let content = IslandClosedArbiter.resolve(
            IslandClosedInputs(waiting: waitingPeek(), timer: timerInput, now: epoch.addingTimeInterval(60))
        )

        #expect(content.body == .waiting(waitingPeek()))
        if case .timer(let minutes, let label) = content.accessory {
            #expect(minutes == snapshot?.remainingMinutes)
            #expect(label == "WORK")
        } else {
            Issue.record("expected a .timer accessory, got \(String(describing: content.accessory))")
        }
    }

    @Test("An idle timer contributes no accessory input at all")
    func idleTimerHasNoSnapshot() {
        #expect(FocusTimerState.idle.snapshot(at: epoch) == nil)

        let content = IslandClosedArbiter.resolve(
            IslandClosedInputs(waiting: waitingPeek(), timer: nil, now: epoch)
        )
        #expect(content.accessory == nil)
    }
}
