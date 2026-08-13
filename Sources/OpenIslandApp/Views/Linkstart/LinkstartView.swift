import OpenIslandCore
import SwiftUI

/// The login sequence, drawn over everything.
///
/// Draws from elapsed time rather than from a chain of animations: the
/// choreography lives in `LinkstartSequence`, which is tested, and a dropped
/// frame here changes what one frame looks like instead of putting the sequence
/// out of step with itself.
struct LinkstartView: View {
    let controller: LinkstartOverlayController
    /// False on the screens that are only along for the ride, so the checklist
    /// appears once rather than on every display.
    let showsDetail: Bool

    var body: some View {
        switch controller.stage {
        case .listening:
            listening
        case let .playing(startedAt):
            sequence(startedAt: startedAt)
        }
    }

    /// The dark screen that waits for the words.
    private var listening: some View {
        let theme = IslandThemes.current
        return ZStack {
            VStack(spacing: 18) {
                if showsDetail {
                    Text(LanguageManager.shared.t("linkstart.say"))
                        .font(IslandTypography.mono(size: 30, weight: .bold))
                        .foregroundStyle(theme.paper)
                        .tracking(10)
                        .shadow(color: theme.accent.opacity(0.7), radius: theme.glowRadius * 2)

                    if let heard = controller.heard {
                        Text(heard)
                            .font(IslandTypography.mono(size: 15))
                            .foregroundStyle(theme.paper.opacity(0.45))
                    }

                    Text(LanguageManager.shared.t("linkstart.dismiss"))
                        .font(IslandTypography.mono(size: 12))
                        .foregroundStyle(theme.paper.opacity(0.3))
                        .tracking(3)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.62))
        .ignoresSafeArea()
    }

    private func sequence(startedAt: Date) -> some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(startedAt)
            let phase = LinkstartSequence.phase(at: elapsed)
            let theme = IslandThemes.current

            ZStack {
                backdrop(elapsed: elapsed, theme: theme)

                if showsDetail {
                    VStack(spacing: 34) {
                        title(elapsed: elapsed, theme: theme)
                        checklist(elapsed: elapsed, theme: theme)
                        trailer(phase: phase, theme: theme)
                    }
                    .padding(60)
                }

                if theme.scanlineIntensity > 0 {
                    Scanlines(intensity: theme.scanlineIntensity)
                        .allowsHitTesting(false)
                }
            }
            .background(.black.opacity(0.62))
            .ignoresSafeArea()
        }
    }

    // MARK: - Pieces

    /// The light that arrives from above before anything is asked of you.
    private func backdrop(elapsed: TimeInterval, theme: any IslandTheme) -> some View {
        Canvas { context, size in
            let descent = min(1, max(0, elapsed / LinkstartSequence.awakeningDuration))
            let headY = size.height * descent

            // A soft column, brightest where the light currently is.
            let column = Gradient(stops: [
                .init(color: theme.accent.opacity(0), location: 0),
                .init(color: theme.accent.opacity(0.30), location: 0.55),
                .init(color: theme.accent.opacity(0.02), location: 1),
            ])
            context.fill(
                Path(CGRect(x: 0, y: 0, width: size.width, height: max(headY, 1))),
                with: .linearGradient(
                    column,
                    startPoint: .init(x: size.width / 2, y: 0),
                    endPoint: .init(x: size.width / 2, y: headY)
                )
            )

            // The leading edge itself, thinning as it settles.
            let edgeOpacity = 0.9 * (1 - descent) + 0.08
            context.stroke(
                Path { path in
                    path.move(to: .init(x: 0, y: headY))
                    path.addLine(to: .init(x: size.width, y: headY))
                },
                with: .color(theme.accent.opacity(edgeOpacity)),
                lineWidth: 1.5
            )

            // A slow pulse under everything, so the screen is never quite still.
            let pulse = 0.06 + 0.03 * sin(elapsed * 1.6)
            context.fill(
                Path(ellipseIn: CGRect(
                    x: size.width / 2 - size.width * 0.4,
                    y: size.height / 2 - size.height * 0.4,
                    width: size.width * 0.8,
                    height: size.height * 0.8
                )),
                with: .radialGradient(
                    Gradient(colors: [theme.accent.opacity(pulse), .clear]),
                    center: .init(x: size.width / 2, y: size.height / 2),
                    startRadius: 0,
                    endRadius: size.width * 0.45
                )
            )
        }
    }

    private func title(elapsed: TimeInterval, theme: any IslandTheme) -> some View {
        Text(LanguageManager.shared.t("linkstart.title"))
            .font(IslandTypography.mono(size: 44, weight: .bold))
            .foregroundStyle(theme.paper)
            .tracking(14)
            .shadow(color: theme.accent.opacity(0.8), radius: theme.glowRadius * 3)
            .opacity(min(1, max(0, elapsed / 0.6)))
    }

    private func checklist(elapsed: TimeInterval, theme: any IslandTheme) -> some View {
        let confirmed = LinkstartSequence.confirmedSenseCount(at: elapsed)

        return VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(LinkstartSequence.senses.enumerated()), id: \.element) { index, sense in
                HStack(spacing: 14) {
                    Image(systemName: index < confirmed ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15))
                        .foregroundStyle(index < confirmed ? theme.accent : theme.paper.opacity(0.28))

                    Text(LanguageManager.shared.t(sense.labelKey))
                        .font(IslandTypography.mono(size: 17))
                        .foregroundStyle(index < confirmed ? theme.paper : theme.paper.opacity(0.35))
                        .tracking(4)

                    Spacer(minLength: 40)

                    Text(index < confirmed ? "OK" : "……")
                        .font(IslandTypography.mono(size: 15))
                        .foregroundStyle(index < confirmed ? theme.accent : theme.paper.opacity(0.25))
                }
                .frame(width: 320)
                .shadow(
                    color: index < confirmed ? theme.accent.opacity(0.5) : .clear,
                    radius: theme.glowRadius
                )
            }
        }
    }

    /// What the sequence says about you once the body checks out.
    @ViewBuilder
    private func trailer(phase: LinkstartPhase, theme: any IslandTheme) -> some View {
        VStack(spacing: 10) {
            switch phase {
            case .awakening, .senses:
                Text(LanguageManager.shared.t("linkstart.checking"))
                    .foregroundStyle(theme.paper.opacity(0.5))
            case .language:
                Text(LanguageManager.shared.t("linkstart.language"))
                    .foregroundStyle(theme.paper)
            case .identity, .complete:
                Text(LanguageManager.shared.t("linkstart.welcome").replacingOccurrences(
                    of: "{name}",
                    with: NSFullUserName()
                ))
                .foregroundStyle(theme.paper)
                .shadow(color: theme.accent.opacity(0.8), radius: theme.glowRadius * 2)
            }

            Text(LanguageManager.shared.t("linkstart.dismiss"))
                .font(IslandTypography.mono(size: 12))
                .foregroundStyle(theme.paper.opacity(0.3))
        }
        .font(IslandTypography.mono(size: 16))
        .tracking(3)
        .animation(theme.animationProfile.open, value: phase)
    }
}

/// Horizontal lines three points apart, the same texture the island uses.
private struct Scanlines: View {
    let intensity: Double

    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                context.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                    with: .color(.black.opacity(intensity))
                )
                y += 3
            }
        }
    }
}
