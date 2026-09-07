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
            .background(theme.shape(cornerRadius: 10).fill(backgroundColor))
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

    private var accentLine: Color {
        switch kind {
        case .primary: theme.ink.opacity(0.55)
        case .warning: V6Palette.paper.opacity(0.7)
        case .secondary: theme.accent
        }
    }

    private var glowColor: Color {
        guard isLit else { return .clear }
        return kind == .secondary ? theme.accent.opacity(0.4) : .clear
    }

    private var foregroundColor: Color {
        guard isEnabled else { return theme.paper.opacity(0.42) }

        switch kind {
        case .primary: return theme.ink.opacity(0.9)
        case .warning: return theme.paper
        case .secondary: return theme.paper.opacity(isLit ? 1 : 0.78)
        }
    }

    private var strokeColor: Color {
        guard isEnabled else { return V6Palette.paper.opacity(0.07) }

        switch kind {
        case .primary:
            return theme.paper.opacity(0.86)
        case .warning:
            return theme.statusTints.waitingForApproval.opacity(isLit ? 0.85 : 0.42)
        case .secondary:
            return isLit ? theme.accent.opacity(0.55) : V6Palette.paper.opacity(0.07)
        }
    }

    private var backgroundColor: Color {
        guard isEnabled else { return V6Palette.paper.opacity(0.055) }

        let pressedFactor: Double = isPressed ? 0.78 : 1
        switch kind {
        case .primary:
            return theme.paper.opacity(pressedFactor)
        case .warning:
            return theme.statusTints.waitingForApproval
                .opacity(pressedFactor * (isLit ? 1 : 0.88))
        case .secondary:
            if isPressed { return V6Palette.paper.opacity(0.14) }
            return isLit ? theme.accent.opacity(0.14) : V6Palette.paper.opacity(0.065)
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
