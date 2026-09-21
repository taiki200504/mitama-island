import OpenIslandCore
import SwiftUI

/// Drives a pulse that ends by itself after `AttentionPulse.duration`.
///
/// `pulse` swings while the cap runs; `settled` flips once it is over, and a
/// view reads both — settling to a *different* value with a plain animation is
/// what replaces the repeating one, since re-assigning the same value would
/// leave it running. Restarts whenever `trigger` changes. Under Reduce Motion
/// it settles at once.
///
/// The swing is a **finite** repeat, not `repeatForever`. `settled` only hides
/// the swing; it does not stop it, and a `repeatForever` animation keeps asking
/// SwiftUI for an update every display frame until the property it animates is
/// re-assigned. On the always-on-screen island that is a layout pass per frame
/// forever — measured at 240 a second, which doubled WindowServer's load and
/// made the pointer drop motion. The cap cannot be relied on to end it either:
/// the triggers here (the waiting count, the peek label) change often enough
/// that the pulse restarts before its own `Task.sleep` ever returns. A count
/// that runs out on its own is the only thing that survives that.
/// `AttentionPulse.repeatCount` already sizes it — `UnifiedBars` uses the same
/// helper for the Core Animation side.
struct CappedPulse<Trigger: Equatable>: ViewModifier {
    @Binding var pulse: Bool
    @Binding var settled: Bool
    let isActive: Bool
    let period: TimeInterval
    let trigger: Trigger

    func body(content: Content) -> some View {
        content.task(id: TaskKey(isActive: isActive, trigger: trigger)) {
            guard isActive, !IslandMotion.reducesMotion else {
                settled = true
                return
            }
            settled = false
            pulse = false
            withAnimation(
                .easeInOut(duration: period)
                    .repeatCount(Int(AttentionPulse.repeatCount(period: period)), autoreverses: true)
            ) {
                pulse = true
            }
            try? await Task.sleep(for: .seconds(AttentionPulse.duration))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) {
                settled = true
            }
        }
    }

    private struct TaskKey: Equatable {
        let isActive: Bool
        let trigger: Trigger
    }
}

extension View {
    func cappedPulse<Trigger: Equatable>(
        _ pulse: Binding<Bool>,
        settled: Binding<Bool>,
        isActive: Bool,
        period: TimeInterval,
        restartOn trigger: Trigger
    ) -> some View {
        modifier(CappedPulse(pulse: pulse, settled: settled, isActive: isActive, period: period, trigger: trigger))
    }
}
