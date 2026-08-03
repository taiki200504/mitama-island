import SwiftUI

/// The monospaced capsule that carries a control's current value on the trailing
/// edge of its row.
///
/// Monospaced on purpose: these values change as the user drags, and a
/// proportional font makes the row twitch sideways on every step.
struct SettingsValuePill: View {
    let text: String
    var isDefault: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
            if isDefault {
                Text(LanguageManager.shared.t("settings.value.defaultMarker"))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .monospacedDigit()
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.08), in: Capsule())
    }
}
