import Foundation

/// Holds a repeating timer outside any actor so `deinit` can stop it.
///
/// A repeating timer that outlives its owner keeps waking the app forever, and
/// `deinit` is not allowed to touch main-actor state to cancel one.
final class RepeatingTimerBox: @unchecked Sendable {
    var timer: Timer?

    deinit { timer?.invalidate() }

    func invalidate() {
        timer?.invalidate()
        timer = nil
    }
}
