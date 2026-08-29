import CoreGraphics
import Foundation
import Observation

/// How long since the keyboard, the mouse or the trackpad was last touched.
///
/// `CGEventSource` answers this without any permission at all — it is the same
/// number the screen saver runs on. Everything else that could tell us this
/// (an event tap, accessibility) would ask for the right to watch every
/// keystroke, which is far too much to pay for a clock.
@MainActor
@Observable
final class UserIdleWatcher {
    private(set) var idleSeconds: TimeInterval = 0

    /// Called on every poll. The decision about what idleness means belongs to
    /// whoever is watching, and giving it the existing tick saves a second
    /// timer running alongside this one.
    @ObservationIgnored var onTick: ((TimeInterval) -> Void)?

    @ObservationIgnored private var poll: Task<Void, Never>?

    /// Coarse on purpose. The board appears after minutes, so a fifteen-second
    /// resolution is invisible in the result and costs one syscall a minute.
    private static let interval: Duration = .seconds(15)

    func start() {
        guard poll == nil else { return }
        poll = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let seconds = Self.currentIdleSeconds()
                self.idleSeconds = seconds
                self.onTick?(seconds)
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    func stop() {
        poll?.cancel()
        poll = nil
        idleSeconds = 0
    }

    /// Resets the count without waiting for the next poll, for the moment the
    /// board is dismissed — otherwise it would reappear on the following tick.
    func markActive() {
        idleSeconds = 0
    }

    /// `kCGAnyInputEventType` — keyboard, mouse and trackpad in one call.
    /// Asking per event type and taking the minimum is the same answer with
    /// more calls. It has no Swift name, hence the raw value.
    private static let anyInputEvent = CGEventType(rawValue: ~UInt32(0))!

    private static func currentIdleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInputEvent)
    }
}
