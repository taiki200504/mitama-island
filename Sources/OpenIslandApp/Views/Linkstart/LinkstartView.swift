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
        case let .pinned(elapsed):
            frame(elapsed: elapsed)
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
            frame(elapsed: context.date.timeIntervalSince(startedAt))
        }
    }

    /// Everything the sequence draws, as a pure function of elapsed time.
    /// `sequence(startedAt:)` re-evaluates this every frame from the real
    /// clock; `.pinned(elapsed:)` calls it exactly once, with no
    /// `TimelineView` advancing it afterwards — the harness's screenshot
    /// lands on the frame it asked for rather than on whatever elapsed time
    /// the wall clock had produced by the moment the capture callback ran.
    private func frame(elapsed: TimeInterval) -> some View {
        let phase = LinkstartSequence.phase(at: elapsed)
        let theme = IslandThemes.current
        let reducesMotion = IslandMotion.reducesMotion

        return ZStack {
            backdrop(elapsed: elapsed, reducesMotion: reducesMotion)

            if showsDetail {
                VStack(spacing: 34) {
                    title(elapsed: elapsed, theme: theme)
                    checklist(elapsed: elapsed, theme: theme, reducesMotion: reducesMotion)
                    trailer(phase: phase, theme: theme, reducesMotion: reducesMotion)
                }
                .padding(60)
            }
        }
        .background(.black.opacity(0.62))
        .opacity(LinkstartSequence.fadeOpacity(at: elapsed))
        .ignoresSafeArea()
    }

    // MARK: - Pieces

    /// The opening burst: concentric rings, a ray starburst outlasting them,
    /// then the colour-calibration wash. Reduced motion collapses the rings
    /// and rays into one still frame, held until the checklist itself starts
    /// rather than for just their own animated duration, and skips the wash
    /// entirely — colour changes, even slow ones, are exactly the kind of
    /// motion that setting asks to remove.
    @ViewBuilder
    private func backdrop(elapsed: TimeInterval, reducesMotion: Bool) -> some View {
        if reducesMotion {
            let isBeforeChecklist = elapsed < LinkstartSequence.sensesStart
            Group {
                SAORingView(progress: 1, count: 5, tint: .white, ringTint: Self.ringTint)
                SAORaysView(progress: 1, count: 24, tint: SAOGrammar.Palette.systemCyan, gradient: Self.rayGradient)
            }
            .opacity(isBeforeChecklist ? 1 : 0)
            // A plain cut rather than a fade: this branch exists so nothing
            // here animates.
            .animation(nil, value: isBeforeChecklist)
        } else {
            SAORingView(
                progress: LinkstartSequence.ringProgress(at: elapsed).first ?? 0,
                count: 5,
                tint: .white,
                ringTint: Self.ringTint
            )
            SAORaysView(
                progress: LinkstartSequence.rayProgress(at: elapsed),
                count: 24,
                tint: SAOGrammar.Palette.systemCyan,
                gradient: Self.rayGradient
            )

            // Capped well under full opacity and handed off between colours
            // as a crossfade rather than a cut — see `calibrationFrames`'s
            // own doc comment for why a strobe has no place on a login screen.
            ForEach(Array(LinkstartSequence.calibrationFrames(at: elapsed).enumerated()), id: \.offset) { _, frame in
                Self.calibrationTint(for: frame.step)
                    .opacity(frame.opacity)
                    .ignoresSafeArea()
            }
        }
    }

    /// White for the leading ring, shading to the theme's cyan by the
    /// trailing one — the same "catching up" read the lag gives their timing.
    private static func ringTint(for index: Int) -> Color {
        mixedColor(from: 0xFFFFFF, to: 0x03A9F4, t: Double(index) / 4)
    }

    /// Every ray shares this gradient, radiating blue at the centre out
    /// through cyan to white at the tip.
    private static let rayGradient = Gradient(colors: [
        Color(hex: 0x1E88E5), SAOGrammar.Palette.systemCyan, .white,
    ])

    private static func calibrationTint(for step: CalibrationStep) -> Color {
        switch step {
        case .red: .red
        case .green: .green
        case .blue: .blue
        case .white: .white
        }
    }

    /// Linear interpolation between two `0xRRGGBB` colours. `SAOGrammar`'s own
    /// palette has no mixing helper, and reaching for one just for this
    /// five-step ring gradient isn't worth adding one there.
    private static func mixedColor(from: UInt32, to: UInt32, t: Double) -> Color {
        let t = min(max(t, 0), 1)
        func component(_ hex: UInt32, _ shift: Int) -> Double {
            Double((hex >> shift) & 0xFF) / 255
        }
        return Color(
            red: component(from, 16) + (component(to, 16) - component(from, 16)) * t,
            green: component(from, 8) + (component(to, 8) - component(from, 8)) * t,
            blue: component(from, 0) + (component(to, 0) - component(from, 0)) * t
        )
    }

    private func title(elapsed: TimeInterval, theme: SAOTheme) -> some View {
        let text = LanguageManager.shared.t("linkstart.title")
        return Text(text)
            .saoCaps(size: 44, text: text)
            .foregroundStyle(theme.paper)
            .shadow(color: theme.accent.opacity(0.8), radius: theme.glowRadius * 3)
            .opacity(min(1, max(0, elapsed / 0.6)))
    }

    private func checklist(elapsed: TimeInterval, theme: SAOTheme, reducesMotion: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(LinkstartSequence.senses.enumerated()), id: \.element) { index, sense in
                senseRow(index: index, sense: sense, elapsed: elapsed, theme: theme, reducesMotion: reducesMotion)
            }
        }
    }

    private static let senseTileShape = SAOPanelShape(
        cornerRadius: 6,
        cuts: [.topLeading, .bottomTrailing],
        cutDepth: 10
    )

    /// One row of the checklist, tiled in the crystal-HUD grammar. Drops in
    /// from above with a left-to-right width wipe the moment its own sense
    /// starts confirming — plain opacity under reduced motion, and hidden
    /// (rather than dim) before its moment, so the checklist fills in one row
    /// at a time instead of sitting there half-lit from the very start.
    @ViewBuilder
    private func senseRow(
        index: Int,
        sense: LinkstartSense,
        elapsed: TimeInterval,
        theme: SAOTheme,
        reducesMotion: Bool
    ) -> some View {
        let confirmed = LinkstartSequence.confirmedSenseCount(at: elapsed)
        let isConfirmed = index < confirmed
        let entrance = Self.senseEntranceProgress(index: index, elapsed: elapsed)

        let row = HStack(spacing: 14) {
            Image(systemName: isConfirmed ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15))
                .foregroundStyle(isConfirmed ? theme.accent : theme.paper.opacity(0.28))

            Text(LanguageManager.shared.t(sense.labelKey))
                .font(IslandTypography.mono(size: 17))
                .foregroundStyle(isConfirmed ? theme.paper : theme.paper.opacity(0.35))
                .tracking(4)

            Spacer(minLength: 40)

            Text(isConfirmed ? "OK" : "……")
                .font(IslandTypography.mono(size: 15))
                .foregroundStyle(isConfirmed ? theme.accent : theme.paper.opacity(0.25))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(width: 320, alignment: .leading)
        .background(Self.senseTileShape.fill(Color.black.opacity(0.3)))
        .clipShape(Self.senseTileShape)
        .saoOutline(Self.senseTileShape, scale: 1.0)
        .shadow(
            color: isConfirmed ? theme.accent.opacity(0.5) : .clear,
            radius: theme.glowRadius
        )

        if reducesMotion {
            row.opacity(entrance > 0 ? 1 : 0)
        } else {
            row
                .offset(y: -12 * (1 - entrance))
                .mask(Rectangle().scaleEffect(x: entrance, y: 1, anchor: .leading))
        }
    }

    private static func senseEntranceProgress(index: Int, elapsed: TimeInterval) -> Double {
        let start = LinkstartSequence.sensesStart + Double(index) * LinkstartSequence.perSenseDuration
        guard elapsed > start else { return 0 }
        return min((elapsed - start) / 0.25, 1)
    }

    /// What the sequence says about you once the body checks out.
    @ViewBuilder
    private func trailer(phase: LinkstartPhase, theme: SAOTheme, reducesMotion: Bool) -> some View {
        VStack(spacing: 10) {
            switch phase {
            case .awakening, .rings, .rays, .calibration, .senses:
                Text(LanguageManager.shared.t("linkstart.checking"))
                    .foregroundStyle(theme.paper.opacity(0.5))
            case .language:
                Text(LanguageManager.shared.t("linkstart.language"))
                    .foregroundStyle(theme.paper)
            case .identity, .fade, .complete:
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
        .animation(reducesMotion ? nil : theme.animationProfile.open, value: phase)
    }
}
