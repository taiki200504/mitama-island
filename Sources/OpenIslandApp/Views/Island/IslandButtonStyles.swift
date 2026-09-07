import SwiftUI
import OpenIslandCore

// MARK: - Compact button style

private struct IslandCompactButtonStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.islandText(size: 10, weight: .semibold))
            .foregroundStyle(tint == .secondary ? V6Palette.paper.opacity(0.7) : tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                (tint == .secondary ? V6Palette.paper.opacity(0.08) : tint.opacity(0.15)),
                in: Capsule()
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The buttons on an approval or question card.
///
/// A `ButtonStyle` cannot hold `@State`, so the hover treatment lives in a
/// nested view. Before this, the only feedback a button gave was a dip in
/// opacity *after* it had been clicked — nothing told you it was pressable
/// while your cursor was on it, which is what made the panel feel dead.
struct IslandActionButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
        case warning
    }

    let kind: Kind
    var expands = false

    func makeBody(configuration: Configuration) -> some View {
        IslandActionButtonBody(kind: kind, expands: expands, configuration: configuration)
    }
}

private struct IslandActionButtonBody: View {
    let kind: IslandActionButtonStyle.Kind
    let expands: Bool
    let configuration: ButtonStyle.Configuration

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    private var theme: SAOTheme { IslandThemes.current }
    private var isPressed: Bool { configuration.isPressed }
    /// A disabled button must not light up under the cursor — that would
    /// promise something it cannot do.
    private var isLit: Bool { isHovering && isEnabled }

    var body: some View {
        configuration.label
            .font(.islandText(size: 11.8, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .frame(maxWidth: expands ? .infinity : nil)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background {
                if kind == .primary, isEnabled {
                    theme.shape(cornerRadius: 10).fill(SAOGrammar.selectionGradient)
                        .opacity(isPressed ? 0.78 : 1)
                } else {
                    theme.shape(cornerRadius: 10).fill(backgroundColor)
                }
            }
            .overlay(theme.shape(cornerRadius: 10).stroke(strokeColor, lineWidth: 1))
            .overlay(alignment: .bottomLeading) { hoverUnderline }
            .clipShape(theme.shape(cornerRadius: 10))
            // A press has to feel like the button moved, not merely faded.
            .scaleEffect(isPressed ? 0.97 : 1)
            .shadow(color: glowColor, radius: isLit ? theme.glowRadius * 2 : 0)
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .animation(.easeOut(duration: 0.08), value: isPressed)
            .onHover { isHovering = $0 }
    }

    /// A one-pixel line that grows in from the left edge. Cheap to draw, and it
    /// reads as the control waking up rather than merely changing colour.
    @ViewBuilder
    private var hoverUnderline: some View {
        Rectangle()
            .fill(accentLine)
            .frame(height: 1.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .scaleEffect(x: isLit ? 1 : 0, anchor: .leading)
            .opacity(isLit ? 1 : 0)
    }

    /// These buttons only ever sit on the white cards `saoCard` draws
    /// (approval and question), never on the dark shell directly, so every
    /// colour below is chosen against a white ground rather than `ink`.
    private var accentLine: Color {
        switch kind {
        case .primary: SAOGrammar.Palette.ink.opacity(0.55)
        case .warning: SAOGrammar.Palette.ink.opacity(0.7)
        case .secondary: theme.accent
        }
    }

    private var glowColor: Color {
        guard isLit else { return .clear }
        return kind == .secondary ? theme.accent.opacity(0.4) : .clear
    }

    private var foregroundColor: Color {
        guard isEnabled else { return SAOGrammar.Palette.ink.opacity(0.32) }

        switch kind {
        case .primary: return SAOGrammar.Palette.ink.opacity(0.9)
        // The warning fill is a saturated yellow — it needs dark text for
        // contrast, not the pale text that reads fine on `ink`.
        case .warning: return SAOGrammar.Palette.ink.opacity(0.92)
        case .secondary: return SAOGrammar.Palette.ink.opacity(isLit ? 0.92 : 0.72)
        }
    }

    private var strokeColor: Color {
        guard isEnabled else { return SAOGrammar.Palette.ink.opacity(0.08) }

        switch kind {
        case .primary:
            return SAOGrammar.Palette.ink.opacity(0.3)
        case .warning:
            return theme.statusTints.waitingForApproval.opacity(isLit ? 0.9 : 0.55)
        case .secondary:
            return isLit ? theme.accent.opacity(0.55) : SAOGrammar.Palette.ink.opacity(0.12)
        }
    }

    private var backgroundColor: Color {
        guard isEnabled else { return SAOGrammar.Palette.ink.opacity(0.05) }

        let pressedFactor: Double = isPressed ? 0.78 : 1
        switch kind {
        case .primary:
            // Unreachable while enabled: the view body draws the primary
            // fill itself (`SAOGrammar.selectionGradient`), since a gradient
            // isn't a `Color`. The `isEnabled` guard above already covers the
            // disabled case, so this only exists to keep the switch exhaustive.
            return .clear
        case .warning:
            return theme.statusTints.waitingForApproval
                .opacity(pressedFactor * (isLit ? 1 : 0.88))
        case .secondary:
            if isPressed { return SAOGrammar.Palette.ink.opacity(0.12) }
            return isLit ? theme.accent.opacity(0.14) : SAOGrammar.Palette.ink.opacity(0.045)
        }
    }
}

struct DismissButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.islandText(size: 12))
                .foregroundStyle(V6Palette.paper.opacity(isHovered ? 0.8 : 0.4))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
