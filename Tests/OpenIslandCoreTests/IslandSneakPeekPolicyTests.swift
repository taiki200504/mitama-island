import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Sneak-peek policy")
struct IslandSneakPeekPolicyTests {
    private let epoch = Date(timeIntervalSince1970: 1_000_000)

    private func peek(_ kind: IslandSneakPeekKind, until: Date, text: String = "") -> IslandSneakPeek {
        IslandSneakPeek(kind: kind, text: text, icon: "circle", until: until)
    }

    @Test("A higher kind replaces a lower one that is still showing")
    func higherReplacesLower() {
        let current = peek(.shelf, until: epoch.addingTimeInterval(10))
        let candidate = peek(.hudGauge, until: epoch.addingTimeInterval(1))
        #expect(IslandSneakPeekPolicy.replace(current: current, with: candidate, now: epoch) == candidate)
    }

    @Test("An equal kind also replaces the one showing")
    func equalKindReplaces() {
        let current = peek(.shelf, until: epoch.addingTimeInterval(10), text: "old")
        let candidate = peek(.shelf, until: epoch.addingTimeInterval(1), text: "new")
        #expect(IslandSneakPeekPolicy.replace(current: current, with: candidate, now: epoch) == candidate)
    }

    @Test("A lower kind arriving while a higher one is active is dropped")
    func lowerIsDroppedWhileHigherActive() {
        let current = peek(.hudGauge, until: epoch.addingTimeInterval(10))
        let candidate = peek(.shelf, until: epoch.addingTimeInterval(1))
        #expect(IslandSneakPeekPolicy.replace(current: current, with: candidate, now: epoch) == current)
    }

    @Test("timerDone is also dropped by a higher active kind — the caller is responsible for re-showing it")
    func timerDoneDroppedLikeAnythingElse() {
        let current = peek(.lockScan, until: epoch.addingTimeInterval(10))
        let candidate = peek(.timerDone, until: epoch.addingTimeInterval(1))
        #expect(IslandSneakPeekPolicy.replace(current: current, with: candidate, now: epoch) == current)
    }

    @Test("A candidate always wins when nothing is currently showing")
    func candidateWinsWhenNothingShowing() {
        let candidate = peek(.shelf, until: epoch.addingTimeInterval(1))
        #expect(IslandSneakPeekPolicy.replace(current: nil, with: candidate, now: epoch) == candidate)
    }

    @Test("A candidate always wins once the current one has expired, regardless of rank")
    func candidateWinsOnceCurrentExpired() {
        let current = peek(.hudGauge, until: epoch.addingTimeInterval(-1))
        let candidate = peek(.shelf, until: epoch.addingTimeInterval(1))
        #expect(IslandSneakPeekPolicy.replace(current: current, with: candidate, now: epoch) == candidate)
    }

    @Test("expired is true for nil, false before `until`, true at and after `until`")
    func expiredBoundary() {
        let peek = peek(.shelf, until: epoch)
        #expect(IslandSneakPeekPolicy.expired(nil, now: epoch))
        #expect(!IslandSneakPeekPolicy.expired(peek, now: epoch.addingTimeInterval(-0.001)))
        #expect(IslandSneakPeekPolicy.expired(peek, now: epoch))
        #expect(IslandSneakPeekPolicy.expired(peek, now: epoch.addingTimeInterval(0.001)))
    }

    @Test(
        "Each kind's duration matches the design",
        arguments: [
            (IslandSneakPeekKind.hudGauge, 1.2),
            (IslandSneakPeekKind.lockScan, 2.2),
            (IslandSneakPeekKind.timerDone, 4.0),
            (IslandSneakPeekKind.eventStarting, 4.0),
            (IslandSneakPeekKind.trackChanged, 1.8),
            (IslandSneakPeekKind.shelf, 1.2),
        ]
    )
    func durations(case pair: (IslandSneakPeekKind, TimeInterval)) {
        #expect(IslandSneakPeekPolicy.duration(for: pair.0) == pair.1)
    }

    @Test("Kind ordering is the raw priority, not declaration order")
    func kindOrdering() {
        #expect(IslandSneakPeekKind.shelf < .trackChanged)
        #expect(IslandSneakPeekKind.trackChanged < .eventStarting)
        #expect(IslandSneakPeekKind.eventStarting < .timerDone)
        #expect(IslandSneakPeekKind.timerDone < .lockScan)
        #expect(IslandSneakPeekKind.lockScan < .hudGauge)
    }
}
