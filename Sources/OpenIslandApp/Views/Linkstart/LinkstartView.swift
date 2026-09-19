import OpenIslandCore
import SwiftUI

/// The login sequence, drawn over everything.
///
/// Draws from elapsed time rather than from a chain of animations: the
/// choreography lives in `LinkstartSequence`, which is tested, and a dropped
/// frame here changes what one frame looks like instead of putting the sequence
/// out of step with itself.
///
/// The SAO (Sword Art Online) NerveGear boot sequence aesthetic: a white field
/// with radiating light wedges, then a light HUD that scales up with concentric
/// rings as each sense confirms.
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
        let reducesMotion = IslandMotion.reducesMotion

        return ZStack {
            // White/pale ground throughout the entire sequence
            Color(hex: 0xF5F8FA)

            // Wedge tunnel (0-3.5s: ignition + warp + flash)
            LinkstartWedgeTunnelView(elapsed: elapsed, reducesMotion: reducesMotion)
                .opacity(elapsed < LinkstartSequence.calibrationStart ? 1 : 0)

            // Light HUD (3.5s onwards: calibration, senses, language, identity)
            if showsDetail {
                LinkstartLightHUDView(
                    elapsed: elapsed,
                    phase: phase,
                    reducesMotion: reducesMotion
                )
            }

            // Fade to white at the end
            Color.white
                .opacity(max(0, (elapsed - LinkstartSequence.fadeStart) / LinkstartSequence.fadeDuration))
        }
        .opacity(LinkstartSequence.fadeOpacity(at: elapsed))
        .ignoresSafeArea()
    }
}

/// The wedge tunnel: multicolored wedges radiating from the center, growing
/// from tiny slivers to large wedges, mimicking the NerveGear boot sequence.
private struct LinkstartWedgeTunnelView: View {
    let elapsed: TimeInterval
    let reducesMotion: Bool

    private static let wedgeCount = 8
    private static let colors: [Color] = [
        .red,
        Color(hex: 0xFF00FF),  // magenta
        .cyan,
        .green,
        .black,
        Color(hex: 0xFFFF00),  // yellow
        Color(hex: 0xFF7F00),  // orange
        Color(hex: 0x7F00FF)   // violet
    ]

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxRadius = (size.width * size.width + size.height * size.height).squareRoot() / 2

            // Map the existing sequence phases to visual progression:
            // Phase 1 (0-0.5s / ignition): tiny slivers at center growing slowly
            // Phase 2 (0.5-3.0s / warp): slivers become thick wedges radiating outward
            // Phase 3 (3.0-3.5s / flash): white-out (wedges fade to white opacity)

            let ignitionEnd = LinkstartSequence.ignitionDuration
            let warpEnd = LinkstartSequence.warpEnd
            let calibrationStart = LinkstartSequence.calibrationStart

            if elapsed < calibrationStart {
                for (index, color) in Self.colors.enumerated() {
                    let angle = Double(index) / Double(Self.colors.count) * 2 * .pi
                    let nextAngle = Double(index + 1) / Double(Self.colors.count) * 2 * .pi

                    // Calculate wedge size based on phase
                    var progress: Double
                    var opacity: Double = 1.0

                    if elapsed < ignitionEnd {
                        // Phase 1 (ignition): tiny slivers growing
                        progress = elapsed / ignitionEnd * 0.15
                    } else if elapsed < warpEnd {
                        // Phase 2 (warp): wedges expanding outward
                        let warpProgress = (elapsed - ignitionEnd) / LinkstartSequence.warpDuration
                        progress = 0.15 + warpProgress * 0.85
                    } else {
                        // Phase 3 (flash): wedges fade out as white-out comes in
                        let flashProgress = (elapsed - warpEnd) / LinkstartSequence.flashDuration
                        progress = 1.0
                        opacity = max(0, 1 - flashProgress * 1.5)
                    }

                    let radius = maxRadius * progress
                    if radius <= 0 || opacity <= 0.01 { continue }

                    let startAngle = angle
                    let endAngle = nextAngle
                    let dx1 = cos(startAngle)
                    let dy1 = sin(startAngle)
                    let dx2 = cos(endAngle)
                    let dy2 = sin(endAngle)

                    var path = Path()
                    path.move(to: center)
                    path.addLine(to: CGPoint(x: center.x + dx1 * radius, y: center.y + dy1 * radius))
                    path.addLine(to: CGPoint(x: center.x + dx2 * radius, y: center.y + dy2 * radius))
                    path.closeSubpath()

                    context.fill(path, with: .color(color.opacity(opacity)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// The light HUD: concentric rings and arc segments with sense indicators,
/// scaling up from the center as it appears after the white-out.
private struct LinkstartLightHUDView: View {
    let elapsed: TimeInterval
    let phase: LinkstartPhase
    let reducesMotion: Bool

    var body: some View {
        let flashOpacity = LinkstartSequence.flashOpacity(at: elapsed)
        let checklistOpacity = LinkstartSequence.checklistOpacity(at: elapsed)
        let scale = hudScale(at: elapsed)
        let confirmedCount = LinkstartSequence.confirmedSenseCount(at: elapsed)

        ZStack {
            // White-out flash
            if !reducesMotion {
                Color.white
                    .opacity(flashOpacity)
                    .allowsHitTesting(false)
            }

            // Main HUD content
            VStack(spacing: 0) {
                LinkstartHUDContent(
                    elapsed: elapsed,
                    confirmedCount: confirmedCount,
                    reducesMotion: reducesMotion
                )
            }
            .scaleEffect(scale, anchor: .center)
            .opacity(checklistOpacity)
        }
        .allowsHitTesting(false)
    }

    /// HUD scale with ease-out: grows from ~0 to 1 as it appears.
    private func hudScale(at elapsed: TimeInterval) -> CGFloat {
        let hudStart = LinkstartSequence.calibrationStart
        guard elapsed > hudStart else { return 0 }
        let scaleProgress = (elapsed - hudStart) / (LinkstartSequence.calibrationDuration + 0.2)
        let clampedProgress = min(max(scaleProgress, 0), 1)
        // Ease-out cubic
        let eased = 1 - pow(1 - clampedProgress, 3)
        return eased
    }
}

/// The HUD content: rings, sense indicators, and OK button.
private struct LinkstartHUDContent: View {
    let elapsed: TimeInterval
    let confirmedCount: Int
    let reducesMotion: Bool

    var body: some View {
        ZStack {
            LinkstartHUDRings(confirmedCount: confirmedCount)

            // Sense checklist inside the HUD
            VStack(spacing: 8) {
                ForEach(Array(LinkstartSequence.senses.enumerated()), id: \.element) { index, sense in
                    senseIndicator(index: index, sense: sense, isConfirmed: index < confirmedCount)
                }

                Spacer()
                    .frame(height: 20)

                // OK button at bottom
                Button(action: {}) {
                    Text("OK")
                        .font(IslandTypography.mono(size: 20, weight: .bold))
                        .foregroundStyle(SAOGrammar.Palette.linkstartCyan1)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.1))
                        .border(SAOGrammar.Palette.linkstartCyan1, width: 1)
                }
                .buttonStyle(.plain)
            }
            .padding(40)
            .frame(width: 240, height: 280)
        }
        .frame(width: 240, height: 280)
    }

    private func senseIndicator(index: Int, sense: LinkstartSense, isConfirmed: Bool) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isConfirmed ? SAOGrammar.Palette.linkstartCyan2 : SAOGrammar.Palette.linkstartPale2.opacity(0.3))
                .frame(width: 8, height: 8)

            Text(LanguageManager.shared.t(sense.labelKey))
                .font(IslandTypography.mono(size: 12))
                .foregroundStyle(isConfirmed ? SAOGrammar.Palette.linkstartCyan2 : SAOGrammar.Palette.linkstartPale2.opacity(0.5))
                .tracking(1)

            Spacer()

            if isConfirmed {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(SAOGrammar.Palette.linkstartCyan2)
            }
        }
        .frame(height: 20)
    }
}

/// The HUD rings and arc segments drawn on Canvas.
private struct LinkstartHUDRings: View {
    let confirmedCount: Int

    private static let ringCount = 5
    private static let segmentCount = 12

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            for ringIndex in 0..<Self.ringCount {
                let progress = Double(ringIndex) / Double(Self.ringCount)
                let radius = size.width / 2 * (0.2 + progress * 0.7)

                // Alternate between cyan and lavender
                let ringColor = ringIndex % 2 == 0
                    ? SAOGrammar.Palette.linkstartCyan2
                    : SAOGrammar.Palette.linkstartLavender1

                // Draw ring as arc segments with gaps
                var path = Path()
                let segmentAngle = 2 * .pi / Double(Self.segmentCount)
                let gapAngle = segmentAngle * 0.3

                for segIndex in 0..<Self.segmentCount {
                    let startAngle = Double(segIndex) * segmentAngle
                    let endAngle = startAngle + segmentAngle - gapAngle

                    let arcStart = CGPoint(
                        x: center.x + cos(startAngle) * radius,
                        y: center.y + sin(startAngle) * radius
                    )

                    if segIndex == 0 {
                        path.move(to: arcStart)
                    } else {
                        path.addLine(to: arcStart)
                    }

                    path.addArc(center: center, radius: radius, startAngle: Angle(radians: startAngle), endAngle: Angle(radians: endAngle), clockwise: false)
                }

                context.stroke(path, with: .color(ringColor.opacity(0.6)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }

            // Draw small square markers at regular intervals
            for i in 0..<Self.segmentCount {
                let angle = Double(i) / Double(Self.segmentCount) * 2 * .pi
                let distance = size.width / 2 * 0.4
                let x = center.x + cos(angle) * distance
                let y = center.y + sin(angle) * distance
                let rect = CGRect(x: x - 2, y: y - 2, width: 4, height: 4)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 0.5),
                    with: .color(SAOGrammar.Palette.linkstartCyan2.opacity(0.5))
                )
            }
        }
        .allowsHitTesting(false)
    }
}
