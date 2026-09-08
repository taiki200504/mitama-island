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
    /// Runs the sweep from −W to +W exactly once per hover, rather than
    /// looping for as long as the pointer rests on the button.
    @State private var sweepOffset: CGFloat = -1
    /// Eases from the outline's own resting opacity up to full and back
    /// across a press, rather than the outline simply appearing.
    @State private var glowOpacity: Double = 0.81

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
            .overlay { hoverSweep }
            .clipShape(shape)
            .overlay(pressGlow)
            // A press has to feel like the button moved, not merely faded.
            .scaleEffect(isPressed ? 0.97 : 1)
            .shadow(color: glowColor, radius: isLit ? theme.glowRadius * 2 : 0)
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .animation(.easeOut(duration: 0.08), value: isPressed)
            .onHover { hovering in
                isHovering = hovering
                guard hovering else { return }
                // Runs once per hover, not on every frame the pointer stays.
                sweepOffset = -1
                withAnimation(IslandMotion.selectionSweep) {
                    sweepOffset = 1
                }
            }
            .onChange(of: isPressed) { _, pressed in
                withAnimation(IslandMotion.glowPulse) {
                    glowOpacity = pressed ? 1.0 : 0.81
                }
            }
    }

    /// A soft white band that crosses the button once when the pointer
    /// lands, 40% of the button's own width, travelling from off the
    /// leading edge to off the trailing edge.
    private var hoverSweep: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            LinearGradient(
                colors: [.clear, .white.opacity(0.35), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width * 0.4)
            .offset(x: sweepOffset * width)
        }
        .clipShape(shape)
        .allowsHitTesting(false)
    }

    /// The outer crystal-HUD glow, held at rest and flashed brighter across
    /// a press — the same colour `saoOutline` uses for its own outer ring.
    private var pressGlow: some View {
        shape
            .stroke(SAOGrammar.Palette.outlineGlow, lineWidth: 1.5)
            .blur(radius: 0.6)
            .opacity(isPressed || isLit ? glowOpacity : 0)
            .allowsHitTesting(false)
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
