import OpenIslandCore
import SwiftUI

/// Drives a `repeatForever` pulse that settles after `AttentionPulse.duration`.
///
/// `pulse` swings while the cap runs; `settled` flips once it is over, and a
/// view reads both — settling to a *different* value with a plain animation is
/// what replaces the repeating one, since re-assigning the same value would
/// leave it running. Restarts whenever `trigger` changes. Under Reduce Motion
/// it settles at once.
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
            withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) {
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
