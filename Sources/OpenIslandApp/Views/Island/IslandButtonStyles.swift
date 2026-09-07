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

    /// Which ground this button sits on. Every current call site is inside a
    /// `saoCard` white card, but the dark-shell palette (this style's
    /// original colours) stays the default so a future call site on the ink
    /// shell directly doesn't have to know to opt out of the light-card look.
    enum Surface {
        case darkShell
        case lightCard
    }

    let kind: Kind
    var expands = false
    var surface: Surface = .darkShell

    func makeBody(configuration: Configuration) -> some View {
        IslandActionButtonBody(kind: kind, expands: expands, surface: surface, configuration: configuration)
    }
}

private struct IslandActionButtonBody: View {
    let kind: IslandActionButtonStyle.Kind
    let expands: Bool
    let surface: IslandActionButtonStyle.Surface
    let configuration: ButtonStyle.Configuration

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    private var theme: SAOTheme { IslandThemes.current }
    private var isPressed: Bool { configuration.isPressed }
    /// A disabled button must not light up under the cursor — that would
    /// promise something it cannot do.
    private var isLit: Bool { isHovering && isEnabled }
    /// Every button shares the crystal-HUD's own cut depth (shallower than a
    /// card's) rather than the compat wrapper's size-derived one.
    private var shape: SAOPanelShape {
        SAOPanelShape(cornerRadius: SAOGrammar.Metric.cornerRadius, cutDepth: 8)
    }

    var body: some View {
        configuration.label
            .font(.islandText(size: 11.8, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .frame(maxWidth: expands ? .infinity : nil)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background {
                if surface == .lightCard, kind == .primary, isEnabled {
                    shape.fill(SAOGrammar.selectionGradient)
                        .opacity(isPressed ? 0.78 : 1)
                } else {
                    shape.fill(backgroundColor)
                }
            }
            .overlay(shape.stroke(strokeColor, lineWidth: 1))
            .overlay(alignment: .bottomLeading) { hoverUnderline }
            .clipShape(shape)
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
        switch (surface, kind) {
        case (.lightCard, .primary): SAOGrammar.Palette.ink.opacity(0.55)
        case (.darkShell, .primary): theme.ink.opacity(0.55)
        case (.lightCard, .warning): SAOGrammar.Palette.ink.opacity(0.7)
        case (.darkShell, .warning): V6Palette.paper.opacity(0.7)
        case (_, .secondary): theme.accent
        }
    }

    private var glowColor: Color {
        guard isLit else { return .clear }
        return kind == .secondary ? theme.accent.opacity(0.4) : .clear
    }

    private var foregroundColor: Color {
        switch surface {
        case .lightCard:
            guard isEnabled else { return SAOGrammar.Palette.ink.opacity(0.32) }
            switch kind {
            case .primary: return SAOGrammar.Palette.ink.opacity(0.9)
            // The warning fill is a saturated yellow — it needs dark text for
            // contrast, not the pale text that reads fine on `ink`.
            case .warning: return SAOGrammar.Palette.ink.opacity(0.92)
            case .secondary: return SAOGrammar.Palette.ink.opacity(isLit ? 0.92 : 0.72)
            }
        case .darkShell:
            guard isEnabled else { return theme.paper.opacity(0.42) }
            switch kind {
            case .primary: return theme.ink.opacity(0.9)
            case .warning: return theme.paper
            case .secondary: return theme.paper.opacity(isLit ? 1 : 0.78)
            }
        }
    }

    private var strokeColor: Color {
        switch surface {
        case .lightCard:
            guard isEnabled else { return SAOGrammar.Palette.ink.opacity(0.08) }
            switch kind {
            case .primary:
                return SAOGrammar.Palette.ink.opacity(0.3)
            case .warning:
                return theme.statusTints.waitingForApproval.opacity(isLit ? 0.9 : 0.55)
            case .secondary:
                return isLit ? theme.accent.opacity(0.55) : SAOGrammar.Palette.ink.opacity(0.12)
            }
        case .darkShell:
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
    }

    private var backgroundColor: Color {
        let pressedFactor: Double = isPressed ? 0.78 : 1
        switch surface {
        case .lightCard:
            guard isEnabled else { return SAOGrammar.Palette.ink.opacity(0.05) }
            switch kind {
            case .primary:
                // Unreachable while enabled: the view body draws the primary
                // fill itself (`SAOGrammar.selectionGradient`), since a
                // gradient isn't a `Color`. This only keeps the switch
                // exhaustive for the disabled case above.
                return .clear
            case .warning:
                return theme.statusTints.waitingForApproval
                    .opacity(pressedFactor * (isLit ? 1 : 0.88))
            case .secondary:
                if isPressed { return SAOGrammar.Palette.ink.opacity(0.12) }
                return isLit ? theme.accent.opacity(0.14) : SAOGrammar.Palette.ink.opacity(0.045)
            }
        case .darkShell:
            guard isEnabled else { return V6Palette.paper.opacity(0.055) }
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
