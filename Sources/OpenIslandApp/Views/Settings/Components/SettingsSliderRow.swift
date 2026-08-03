import SwiftUI

/// A label with its live value on the trailing edge and a tick-marked slider
/// underneath.
///
/// The tick dots are what make a continuous range feel like it has detents, and
/// the "reset to default" context action means the user can always get back to a
/// sane value without hunting for the exact number.
struct SettingsSliderRow: View {
    let title: String
    var help: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    var availability: FeatureAvailability = .ready
    let defaultValue: Double
    /// Renders the raw value into what the pill shows, e.g. `"560pt"` or `"0.15s"`.
    let format: (Double) -> String

    private var isAtDefault: Bool {
        abs(value - defaultValue) < (step ?? 0.001) / 2
    }

    private var tickCount: Int { 12 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                        if let capability = availability.pendingCapability {
                            PendingCapabilityBadge(capability: capability)
                        }
                    }
                    if let help, !help.isEmpty {
                        Text(help)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                SettingsValuePill(text: format(value), isDefault: isAtDefault)
            }

            slider

            tickMarks
        }
        .settingsControlAvailability(availability)
        .contextMenu {
            Button(LanguageManager.shared.t("settings.value.reset")) {
                value = defaultValue
            }
            .disabled(isAtDefault)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(format(value))
    }

    @ViewBuilder
    private var slider: some View {
        if let step {
            Slider(value: $value, in: range, step: step)
        } else {
            Slider(value: $value, in: range)
        }
    }

    private var tickMarks: some View {
        HStack(spacing: 0) {
            ForEach(0..<tickCount, id: \.self) { index in
                Circle()
                    .fill(Color.primary.opacity(0.18))
                    .frame(width: 2, height: 2)
                if index < tickCount - 1 {
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 6)
        .accessibilityHidden(true)
    }
}
