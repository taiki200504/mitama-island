import Foundation
import Testing
@testable import OpenIslandCore

@Suite("FocusCardElapsed")
struct FocusCardElapsedTests {
    private let saved = Date(timeIntervalSince1970: 1_000_000)

    @Test("Anything under a minute reads as just now")
    func justNow() {
        #expect(FocusCardElapsed.unit(since: saved, now: saved) == .justNow)
        #expect(FocusCardElapsed.unit(since: saved, now: saved.addingTimeInterval(59)) == .justNow)
    }

    @Test("Each unit takes over exactly where the one below runs out")
    func boundaries() {
        #expect(FocusCardElapsed.unit(since: saved, now: saved.addingTimeInterval(60)) == .minutes(1))
        #expect(FocusCardElapsed.unit(since: saved, now: saved.addingTimeInterval(59 * 60)) == .minutes(59))
        #expect(FocusCardElapsed.unit(since: saved, now: saved.addingTimeInterval(60 * 60)) == .hours(1))
        #expect(FocusCardElapsed.unit(since: saved, now: saved.addingTimeInterval(23 * 3600)) == .hours(23))
        #expect(FocusCardElapsed.unit(since: saved, now: saved.addingTimeInterval(24 * 3600)) == .days(1))
    }

    /// A card saved while the clock was wrong must not read as "in 3 hours".
    @Test("A card from the future reads as just now, not as a negative age")
    func clockWentBackwards() {
        #expect(FocusCardElapsed.unit(since: saved, now: saved.addingTimeInterval(-3600)) == .justNow)
    }
}

@Suite("Closed island: a held interruption")
struct HeldInterruptionAccessoryTests {
    @Test("Shows when nothing else is happening")
    func showsWhenIdle() {
        let content = IslandClosedArbiter.resolve(IslandClosedInputs(holdsInterruption: true))
        #expect(content.accessory == .heldInterruption)
    }

    @Test("Nothing to hold, nothing to show")
    func absentWithoutACard() {
        let content = IslandClosedArbiter.resolve(IslandClosedInputs(holdsInterruption: false))
        #expect(content.accessory == nil)
    }

    /// The card is a place kept for later; everything above it is happening
    /// now, and now wins. The shelf is the closest case — both are things put
    /// down — so it is the one worth pinning.
    @Test("Anything happening beats it")
    func losesToEverythingElse() {
        let shelf = IslandClosedArbiter.resolve(
            IslandClosedInputs(shelfCount: 2, holdsInterruption: true)
        )
        #expect(shelf.accessory == .shelf(count: 2))

        let camera = IslandClosedArbiter.resolve(
            IslandClosedInputs(cameraIsWatching: true, holdsInterruption: true)
        )
        #expect(camera.accessory == .cameraWatching)

        let timer = IslandClosedArbiter.resolve(
            IslandClosedInputs(
                timer: .init(remainingMinutes: 5, label: "work"),
                holdsInterruption: true
            )
        )
        #expect(timer.accessory == .timer(remainingMinutes: 5, label: "work"))
    }
}
