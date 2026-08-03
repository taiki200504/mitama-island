import SwiftUI

/// Marks a control whose engine support has not landed yet.
///
/// Shipping a switch that stores a value but changes nothing is worse than not
/// shipping it: the user flips it, nothing happens, and they stop trusting the
/// rest of the pane. The badge says so plainly and the control stays disabled
/// until `PendingCapability.implemented` grows to include it.
struct PendingCapabilityBadge: View {
    let capability: PendingCapability

    var body: some View {
        Text(LanguageManager.shared.t("settings.pending.badge"))
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.22), in: Capsule())
            .foregroundStyle(.orange)
            .help(LanguageManager.shared.t(capability.explanationKey))
    }
}

extension View {
    /// Disables and dims the control when its capability is still pending.
    @ViewBuilder
    func settingsControlAvailability(_ availability: FeatureAvailability) -> some View {
        if availability.isReady {
            self
        } else {
            self
                .disabled(true)
                .opacity(0.5)
        }
    }
}
