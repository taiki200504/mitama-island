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
                if !reducesMotion {
                    titleSlam(elapsed: elapsed, theme: theme)
                }

                VStack(spacing: 34) {
                    title(elapsed: elapsed, theme: theme)
                    checklist(elapsed: elapsed, theme: theme, reducesMotion: reducesMotion)
                    trailer(elapsed: elapsed, phase: phase, theme: theme, reducesMotion: reducesMotion)
                }
                .padding(60)
                .opacity(reducesMotion ? 1 : LinkstartSequence.checklistOpacity(at: elapsed))
            }

            if !reducesMotion {
                // Above everything, the checklist included: the white-out is
                // the moment of arriving, and nothing should sit on top of it.
                Color.white
                    .opacity(LinkstartSequence.flashOpacity(at: elapsed))
                    .allowsHitTesting(false)
            }
        }
        .background(.black.opacity(reducesMotion ? 0.62 : Self.backdropDarkness(at: elapsed)))
        .opacity(LinkstartSequence.fadeOpacity(at: elapsed))
        .ignoresSafeArea()
    }

    /// Near-black while diving so the light has something to cut through,
    /// easing back to the usual dim once you have arrived.
    private static func backdropDarkness(at elapsed: TimeInterval) -> Double {
        let t = min(max((elapsed - LinkstartSequence.calibrationStart) / 0.3, 0), 1)
        return 0.94 - 0.32 * t
    }

    // MARK: - Pieces

    /// The opening burst: shockwave rings, the tunnel of light, then the
    /// colour-calibration wash. Reduced motion collapses all of it into one
    /// still frame of rings, held until the checklist starts, and skips the
    /// tunnel, the white-out and the wash — exactly the motion that setting
    /// asks to remove.
    @ViewBuilder
    private func backdrop(elapsed: TimeInterval, reducesMotion: Bool) -> some View {
        if reducesMotion {
            let isBeforeChecklist = elapsed < LinkstartSequence.sensesStart
            SAORingView(progress: 1, count: 5, tint: .white, ringTint: Self.ringTint)
                .opacity(isBeforeChecklist ? 1 : 0)
                // A plain cut rather than a fade: this branch exists so nothing
                // here animates.
                .animation(nil, value: isBeforeChecklist)
        } else {
            LinkstartTunnelView(elapsed: elapsed)

            SAORingView(
                progress: LinkstartSequence.ringProgress(at: elapsed).first ?? 0,
                count: 5,
                tint: .white,
                ringTint: Self.ringTint
            )
            .opacity(1 - LinkstartSequence.warpSpeed(at: elapsed))

            // Capped well under full opacity and handed off between colours
            // as a crossfade rather than a cut — see `calibrationFrames`.
            ForEach(Array(LinkstartSequence.calibrationFrames(at: elapsed).enumerated()), id: \.offset) { _, frame in
                Self.calibrationTint(for: frame.step)
                    .opacity(frame.opacity)
                    .ignoresSafeArea()
            }
        }
    }

    /// The big title at the start: slams in with its red and cyan copies
    /// pulled apart, then flies past into the tunnel.
    private func titleSlam(elapsed: TimeInterval, theme: SAOTheme) -> some View {
        let frame = LinkstartSequence.titleSlam(at: elapsed)
        let text = LanguageManager.shared.t("linkstart.title")
        let offset = CGFloat(frame.split) * 14

        return ZStack {
            Text(text).saoCaps(size: 96, text: text)
                .foregroundStyle(Color(red: 1, green: 0.2, blue: 0.35).opacity(0.7))
                .offset(x: -offset)
            Text(text).saoCaps(size: 96, text: text)
                .foregroundStyle(Color(red: 0.2, green: 0.9, blue: 1).opacity(0.7))
                .offset(x: offset)
            Text(text).saoCaps(size: 96, text: text)
                .foregroundStyle(.white)
                .shadow(color: theme.accent, radius: theme.glowRadius * 4)
        }
        .compositingGroup()
        .blendMode(.plusLighter)
        .scaleEffect(frame.scale)
        .opacity(frame.opacity)
        .allowsHitTesting(false)
    }

    /// White for the leading ring, shading to the theme's cyan by the
    /// trailing one — the same "catching up" read the lag gives their timing.
    private static func ringTint(for index: Int) -> Color {
        mixedColor(from: 0xFFFFFF, to: 0x03A9F4, t: Double(index) / 4)
    }

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
    private func trailer(elapsed: TimeInterval, phase: LinkstartPhase, theme: SAOTheme, reducesMotion: Bool) -> some View {
        VStack(spacing: 10) {
            // A bar filling every frame is motion too: held full under Reduce Motion.
            syncMeter(rate: reducesMotion ? 100 : LinkstartSequence.syncRate(at: elapsed), theme: theme)

            switch phase {
            case .awakening, .ignition, .warp, .flash, .calibration, .senses:
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
                .font(IslandTypography.mono(size: 28, weight: .bold))
                .foregroundStyle(theme.paper)
                .shadow(color: theme.accent.opacity(0.9), radius: theme.glowRadius * 3)
            }

            Text(LanguageManager.shared.t("linkstart.dismiss"))
                .font(IslandTypography.mono(size: 12))
                .foregroundStyle(theme.paper.opacity(0.3))
        }
        .font(IslandTypography.mono(size: 16))
        .tracking(3)
        .animation(reducesMotion ? nil : theme.animationProfile.open, value: phase)
    }

    /// A thin bar and a number, filling as the senses check out.
    private func syncMeter(rate: Int, theme: SAOTheme) -> some View {
        VStack(spacing: 6) {
            Text(LanguageManager.shared.t("linkstart.sync").replacingOccurrences(of: "{rate}", with: String(rate)))
                .font(IslandTypography.mono(size: 13))
                .foregroundStyle(rate == 100 ? theme.accent : theme.paper.opacity(0.6))
                .monospacedDigit()
            Capsule()
                .fill(theme.paper.opacity(0.12))
                .frame(width: 320, height: 3)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(theme.accent)
                        .frame(width: 320 * CGFloat(rate) / 100, height: 3)
                        .shadow(color: theme.accent, radius: theme.glowRadius)
                }
        }
        .padding(.bottom, 8)
    }
}

/// The tunnel of light, drawn from `LinkstartSequence.streaks(at:)`.
///
/// Two strokes per streak — a wide faint one under a thin bright one — stand
/// in for a blur, which over a whole screen at display refresh rate would
/// cost far more than it looks.
private struct LinkstartTunnelView: View {
    let elapsed: TimeInterval

    /// Half the diagonal of a 14" laptop screen in points: the size the
    /// line widths were tuned on.
    private static let referenceHalfDiagonal: CGFloat = 900
    private static let hueBuckets = 8
    private static let depthBuckets = 4

    var body: some View {
        let streaks = LinkstartSequence.streaks(at: elapsed)
        let glow = LinkstartSequence.coreGlow(at: elapsed)

        Canvas { context, size in
            guard !streaks.isEmpty else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let halfDiagonal = (size.width * size.width + size.height * size.height).squareRoot() / 2
            context.blendMode = .plusLighter

            // Line widths follow the screen like everything else here, so a
            // 6K display gets the same tunnel as a laptop rather than a thinner one.
            let widthScale = halfDiagonal / Self.referenceHalfDiagonal

            // Batched: one path per hue × depth bucket instead of one stroke
            // per streak, so a frame is a few dozen draw calls, not hundreds,
            // on every screen at display refresh rate.
            var buckets: [Int: (path: Path, opacity: Double, width: Double, hue: Double, count: Int)] = [:]
            for streak in streaks where streak.opacity > 0.01 && streak.outer > streak.inner {
                let hueBucket = min(Int(streak.hue * Double(Self.hueBuckets)), Self.hueBuckets - 1)
                let depthBucket = min(Int(streak.outer / 1.15 * Double(Self.depthBuckets)), Self.depthBuckets - 1)
                let key = hueBucket * Self.depthBuckets + depthBucket
                let direction = CGVector(dx: cos(streak.angle), dy: sin(streak.angle))
                var entry = buckets[key] ?? (Path(), 0, 0, 0, 0)
                entry.path.move(to: CGPoint(
                    x: center.x + direction.dx * halfDiagonal * streak.inner,
                    y: center.y + direction.dy * halfDiagonal * streak.inner
                ))
                entry.path.addLine(to: CGPoint(
                    x: center.x + direction.dx * halfDiagonal * streak.outer,
                    y: center.y + direction.dy * halfDiagonal * streak.outer
                ))
                entry.opacity += streak.opacity
                entry.width += streak.width
                entry.hue += streak.hue
                entry.count += 1
                buckets[key] = entry
            }

            for entry in buckets.values {
                let n = Double(entry.count)
                let opacity = entry.opacity / n
                let width = CGFloat(entry.width / n) * widthScale
                let colour = Color(hue: entry.hue / n, saturation: 0.7, brightness: 1)
                context.stroke(entry.path, with: .color(colour.opacity(opacity * 0.25)), style: StrokeStyle(lineWidth: width * 6, lineCap: .round))
                context.stroke(entry.path, with: .color(.white.opacity(opacity * 0.9)), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }

            let radius = halfDiagonal * 0.35 * CGFloat(0.4 + glow)
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                with: .radialGradient(
                    Gradient(colors: [.white.opacity(glow), Color(hex: 0x03A9F4).opacity(glow * 0.35), .clear]),
                    center: center,
                    startRadius: 0,
                    endRadius: radius
                )
            )
        }
        .allowsHitTesting(false)
    }
}
