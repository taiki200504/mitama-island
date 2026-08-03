import SwiftUI

/// One settings line: a label, optional explanation directly beneath it, and a
/// control on the trailing edge.
///
/// The explanation belongs *inside* the row rather than on a line of its own —
/// that is what keeps a long help string visually attached to the switch it
/// describes instead of floating between two unrelated rows.
struct SettingsRow<Control: View>: View {
    let title: String
    var help: String?
    var icon: String?
    var availability: FeatureAvailability = .ready
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)
            }

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

            control()
                .settingsControlAvailability(availability)
        }
        .accessibilityElement(children: .combine)
    }
}

extension SettingsRow where Control == EmptyView {
    init(
        title: String,
        help: String? = nil,
        icon: String? = nil,
        availability: FeatureAvailability = .ready
    ) {
        self.init(title: title, help: help, icon: icon, availability: availability) { EmptyView() }
    }
}

/// A row whose control is a toggle — by far the most common shape.
struct SettingsToggleRow: View {
    let title: String
    var help: String?
    var icon: String?
    var availability: FeatureAvailability = .ready
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, help: help, icon: icon, availability: availability) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

/// A row whose control is a pop-up menu over a fixed set of cases.
struct SettingsPickerRow<Value: Hashable, Content: View>: View {
    let title: String
    var help: String?
    var availability: FeatureAvailability = .ready
    @Binding var selection: Value
    @ViewBuilder var options: () -> Content

    var body: some View {
        SettingsRow(title: title, help: help, availability: availability) {
            Picker("", selection: $selection) {
                options()
            }
            .labelsHidden()
            .fixedSize()
        }
    }
}
