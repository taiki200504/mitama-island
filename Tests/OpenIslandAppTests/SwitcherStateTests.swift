import Foundation
import Testing
@testable import OpenIslandApp

@Suite("Session switcher")
struct SwitcherStateTests {
    @Test
    func pointingGoesStraightToARowRatherThanSteppingThroughThem() {
        var state = SwitcherState()
        let sessions = ["a", "b", "c"]

        state.point(at: "c", sessions: sessions)

        #expect(state.isActive)
        #expect(state.highlightedID == "c")
        // Confirming takes what the ring is around, not the next one along.
        #expect(state.confirm() == "c")
    }

    @Test
    func pointingAtSomethingThatIsNotThereChangesNothing() {
        var state = SwitcherState()
        state.point(at: "gone", sessions: ["a", "b"])

        #expect(!state.isActive)
        #expect(state.highlightedID == nil)
    }

    private let sessions = ["a", "b", "c"]
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func opened(current: String? = "a", reversed: Bool = false) -> SwitcherState {
        var state = SwitcherState()
        state.open(sessions: sessions, current: current, at: start, reversed: reversed)
        return state
    }

    /// The point of a bare tap: one press gets you to the other session. Opening
    /// on the *current* one would make every switch take two presses.
    @Test("Opening lands on the next session, not the current one")
    func opensOnNext() {
        #expect(opened().highlightedID == "b")
    }

    @Test("Reversed opening lands on the previous one")
    func opensOnPrevious() {
        var state = SwitcherState()
        state.open(sessions: sessions, current: "b", at: start, reversed: true)
        #expect(state.highlightedID == "a")
    }

    @Test("Cycling wraps at both ends")
    func wrapsAround() {
        var state = opened(current: "c")
        #expect(state.highlightedID == "a")
        state.advance(sessions: sessions, reversed: true)
        #expect(state.highlightedID == "c")
    }

    /// A quick tap must leave the list up. Jumping on release would make the
    /// arrow-key mode unreachable.
    @Test("A tap leaves the switcher open")
    func tapStaysOpen() {
        var state = opened()
        let target = state.modifierReleased(at: start.addingTimeInterval(0.1))
        #expect(target == nil)
        #expect(state.isActive)
    }

    @Test("A hold jumps on release")
    func holdJumpsOnRelease() {
        var state = opened()
        state.noteStillHeld(at: start.addingTimeInterval(0.4))
        let target = state.modifierReleased(at: start.addingTimeInterval(0.5))
        #expect(target == "b")
        #expect(state.isActive == false)
    }

    /// Someone who taps twice quickly has clearly chosen; releasing should take
    /// them there even though neither press outlasted the threshold.
    @Test("Navigating makes even a quick release jump")
    func navigationImpliesIntent() {
        var state = opened()
        state.advance(sessions: sessions)
        let target = state.modifierReleased(at: start.addingTimeInterval(0.1))
        #expect(target == "c")
        #expect(state.isActive == false)
    }

    @Test("Confirming jumps to the highlighted session")
    func confirmJumps() {
        var state = opened()
        #expect(state.confirm() == "b")
        #expect(state.isActive == false)
    }

    @Test("Cancelling jumps nowhere")
    func cancelDoesNothing() {
        var state = opened()
        state.cancel()
        #expect(state.isActive == false)
        #expect(state.highlightedID == nil)
    }

    /// The highlight must not be left pointing at a session that ended, or
    /// confirming would jump to something that no longer exists.
    @Test("A vanished highlight moves to a live session")
    func survivesSessionsEnding() {
        var state = opened()
        state.sessionsChanged(to: ["a", "c"])
        #expect(state.highlightedID == "a")
    }

    @Test("Losing every session closes the switcher")
    func closesWhenEmpty() {
        var state = opened()
        state.sessionsChanged(to: [])
        #expect(state.isActive == false)
    }

    @Test("An empty list never opens")
    func neverOpensEmpty() {
        var state = SwitcherState()
        state.open(sessions: [], current: nil, at: start)
        #expect(state.isActive == false)
    }

    @Test("Nothing happens before it is opened")
    func inertWhenClosed() {
        var state = SwitcherState()
        state.advance(sessions: sessions)
        #expect(state.highlightedID == nil)
        #expect(state.confirm() == nil)
        #expect(state.modifierReleased(at: start) == nil)
    }

    /// Exactly at the threshold counts as a hold, so the boundary is not a
    /// no-man's-land where neither gesture happens.
    @Test("The threshold itself counts as holding")
    func thresholdIsInclusive() {
        var state = opened()
        state.noteStillHeld(at: start.addingTimeInterval(SwitcherState.holdThreshold))
        #expect(state.isHolding)
    }
}
