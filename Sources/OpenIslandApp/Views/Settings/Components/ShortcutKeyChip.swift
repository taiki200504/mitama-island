import SwiftUI

/// A single keycap.
struct ShortcutKeyChip: View {
    let label: String
    var isEditable: Bool = false
    var isRecording: Bool = false

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .frame(minWidth: 26)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                if isRecording {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                }
            }
            .foregroundStyle(isRecording ? Color.accentColor : .primary)
    }

    private var background: Color {
        isEditable ? Color.primary.opacity(0.14) : Color.primary.opacity(0.08)
    }
}

/// A panel action and the keys that trigger it: the shared modifier, then the
/// action's own key.
///
/// Clicking an editable key arms it; the next letter or digit typed becomes the
/// assignment. Escape leaves it unchanged.
struct ShortcutAssignmentRow: View {
    let title: String
    var help: String?
    let modifier: ShortcutModifier?
    let keyLabel: String
    /// Assignments store fine today; nothing fires them yet.
    var pendingNote: PendingCapability?
    var onAssign: ((String) -> Void)?

    @State private var isRecording = false

    var body: some View {
        SettingsRow(title: title, help: help, pendingNote: pendingNote) {
            HStack(spacing: 5) {
                if let modifier {
                    ShortcutKeyChip(label: modifier.symbol)
                    Text("+")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                if onAssign != nil {
                    Button {
                        isRecording.toggle()
                    } label: {
                        ShortcutKeyChip(label: keyLabel, isEditable: true, isRecording: isRecording)
                    }
                    .buttonStyle(.plain)
                    // `onKeyPress` only fires on a focused view.
                    .focusable()
                    .focusEffectDisabled()
                    .onKeyPress(phases: .down) { press in
                        guard isRecording else { return .ignored }
                        if press.key == .escape {
                            isRecording = false
                            return .handled
                        }
                        let candidate = ShortcutSettings.normalise(String(press.characters))
                        guard !candidate.isEmpty else { return .ignored }
                        onAssign?(candidate)
                        isRecording = false
                        return .handled
                    }
                } else {
                    ShortcutKeyChip(label: keyLabel)
                }
            }
        }
    }
}
