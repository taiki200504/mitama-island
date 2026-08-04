import Foundation

/// The session switcher's behaviour, as a value.
///
/// Two gestures share one key, and telling them apart is the whole difficulty:
/// a quick tap should leave a list open to arrow through, while holding the
/// modifier should cycle and jump the moment it is released. Keeping that as a
/// pure type means the rule can be tested at exact timings instead of by
/// pressing keys and hoping.
struct SwitcherState: Equatable, Sendable {
    /// Below this, a press is a tap. Above it, the user is holding.
    ///
    /// Long enough that a deliberate tap is never read as a hold; short enough
    /// that holding does not feel like it is ignoring you.
    static let holdThreshold: TimeInterval = 0.3

    private(set) var isActive = false
    private(set) var highlightedID: String?
    /// Whether the user has moved the selection since opening. A tap that never
    /// navigated should still jump to the next session, not stay where it was.
    private(set) var hasNavigated = false
    private(set) var openedAt: Date?
    /// Set once the press outlasts the threshold. Only then does releasing the
    /// modifier jump — otherwise letting go of a quick tap would dismiss the
    /// list the tap just asked for.
    private(set) var isHolding = false

    /// Opens the switcher on the session after the current one.
    ///
    /// Starting on the *next* session rather than the current one is what makes
    /// a bare tap useful: it is "go to the other one" in a single press.
    mutating func open(sessions: [String], current: String?, at date: Date, reversed: Bool = false) {
        guard !sessions.isEmpty else { return }
        isActive = true
        openedAt = date
        hasNavigated = false
        isHolding = false
        highlightedID = Self.step(from: current, in: sessions, reversed: reversed)
    }

    /// Another press while already open moves the selection along.
    mutating func advance(sessions: [String], reversed: Bool = false) {
        guard isActive, !sessions.isEmpty else { return }
        hasNavigated = true
        highlightedID = Self.step(from: highlightedID, in: sessions, reversed: reversed)
    }

    /// Called as time passes while the key is down.
    mutating func noteStillHeld(at date: Date) {
        guard isActive, let openedAt else { return }
        // A millisecond of slack: `Date` arithmetic on a large epoch cannot
        // represent 0.3 exactly, so a press timed at precisely the threshold
        // would otherwise land just under it and be read as a tap.
        if date.timeIntervalSince(openedAt) >= Self.holdThreshold - 0.001 { isHolding = true }
    }

    /// The modifier came up. Returns the session to jump to, or `nil` when the
    /// switcher should stay open for arrow keys.
    mutating func modifierReleased(at date: Date) -> String? {
        guard isActive else { return nil }
        noteStillHeld(at: date)
        // A tap that never grew into a hold leaves the list up. Anything else
        // was a deliberate cycle and ends in a jump.
        guard isHolding || hasNavigated else { return nil }
        let target = highlightedID
        reset()
        return target
    }

    /// Arrow keys, once the list is up.
    mutating func moveSelection(sessions: [String], reversed: Bool) {
        advance(sessions: sessions, reversed: reversed)
    }

    /// Return, or a click on a row.
    mutating func confirm() -> String? {
        guard isActive else { return nil }
        let target = highlightedID
        reset()
        return target
    }

    /// Escape, or the sessions going away underneath it.
    mutating func cancel() {
        reset()
    }

    /// Keeps the highlight on something that still exists.
    mutating func sessionsChanged(to sessions: [String]) {
        guard isActive else { return }
        guard !sessions.isEmpty else {
            reset()
            return
        }
        if let highlightedID, !sessions.contains(highlightedID) {
            self.highlightedID = sessions.first
        }
    }

    private mutating func reset() {
        isActive = false
        highlightedID = nil
        hasNavigated = false
        openedAt = nil
        isHolding = false
    }

    /// One step around the list, wrapping at both ends.
    private static func step(from current: String?, in sessions: [String], reversed: Bool) -> String? {
        guard !sessions.isEmpty else { return nil }
        guard let current, let index = sessions.firstIndex(of: current) else {
            return reversed ? sessions.last : sessions.first
        }
        let offset = reversed ? -1 : 1
        let next = (index + offset + sessions.count) % sessions.count
        return sessions[next]
    }
}
