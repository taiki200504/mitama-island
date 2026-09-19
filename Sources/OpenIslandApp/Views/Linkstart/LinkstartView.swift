import OpenIslandCore
import SwiftUI

/// The login sequence, drawn over everything.
///
/// Draws from elapsed time rather than from a chain of animations: the
/// choreography lives in `LinkstartSequence`, which is tested, and a dropped
/// frame here changes what one frame looks like instead of putting the sequence
/// out of step with itself.
///
/// A white field
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
            // The ground: white while the tunnel runs, tinting to the HUD's
            // blue-white as the rings arrive — the reference is never a flat
            // paper white behind the interface.
            Color.white
            SAOGrammar.Palette.linkstartPale2
                .opacity(elapsed < LinkstartSequence.calibrationStart ? 0 : 1)

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
/// from tiny slivers to streaks rushing past the viewer.
private struct LinkstartWedgeTunnelView: View {
    let elapsed: TimeInterval
    let reducesMotion: Bool

    /// Many thin slivers, not a few fat pie slices: the reference is a field
    /// of streaks of different widths and lengths rushing past the viewer,
    /// and an even eight-way split reads as a colour wheel instead.
    private static let wedgeCount = 46
    private static let palette: [Color] = [
        Color(hex: 0xE8253B),   // red
        Color(hex: 0x00C8E0),   // cyan
        Color(hex: 0xE81DC8),   // magenta
        Color(hex: 0x14C850),   // green
        Color(hex: 0x111111),   // black
        Color(hex: 0xF0D000),   // yellow
        Color(hex: 0xFF7A00),   // orange
        Color(hex: 0x7B3BE8),   // violet
    ]

    /// Fixed per-wedge angle, width, length and speed. Seeded, so the same
    /// elapsed time always draws the same frame — the harness pins frames and
    /// a random field would make every capture a different picture.
    private struct Sliver {
        let angle: Double
        let width: Double
        let lengthScale: Double
        let speed: Double
        let delay: Double
        let colour: Color
    }

    private static let slivers: [Sliver] = {
        var seed: UInt64 = 0x5A0_1EAD
        func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double((seed >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
        }
        return (0..<wedgeCount).map { index in
            Sliver(
                angle: (Double(index) / Double(wedgeCount) + next() * 0.018) * 2 * .pi,
                width: (0.9 + next() * 3.6) * .pi / 180,
                lengthScale: 0.45 + next() * 0.75,
                speed: 0.75 + next() * 0.7,
                delay: next() * 0.28,
                colour: palette[index % palette.count]
            )
        }
    }()

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let reach = (size.width * size.width + size.height * size.height).squareRoot() / 2
            let warpEnd = LinkstartSequence.warpEnd
            let calibrationStart = LinkstartSequence.calibrationStart
            guard elapsed < calibrationStart else { return }

            // 0 → the slivers are a speck at the centre; 1 → they have left
            // the screen. Cubed, because the reference accelerates: barely
            // moving for the first second, gone in the last half.
            let travel = pow(max(0, min(elapsed / warpEnd, 1)), 2.6)
            let fade = elapsed <= warpEnd
                ? 1
                : max(0, 1 - (elapsed - warpEnd) / max(LinkstartSequence.flashDuration, 0.001) * 1.6)

            for sliver in Self.slivers {
                let own = max(0, travel - sliver.delay * 0.35) * sliver.speed
                guard own > 0.0005 else { continue }
                // Tail and head both travel; the gap between them is the
                // streak, and it stretches as the thing speeds up.
                let head = min(own * 1.6, 1.9) * reach * sliver.lengthScale + 6
                let tail = max(0, own - 0.16 * sliver.speed) * reach * sliver.lengthScale
                guard head > tail else { continue }

                let half = sliver.width / 2
                let a0 = sliver.angle - half
                let a1 = sliver.angle + half
                // Pointed at the centre, wide at the leading edge — the
                // reference's wedges are triangles aimed inwards.
                var path = Path()
                path.move(to: CGPoint(x: center.x + cos(sliver.angle) * tail,
                                      y: center.y + sin(sliver.angle) * tail))
                path.addLine(to: CGPoint(x: center.x + cos(a0) * head, y: center.y + sin(a0) * head))
                path.addLine(to: CGPoint(x: center.x + cos(a1) * head, y: center.y + sin(a1) * head))
                path.closeSubpath()

                context.fill(path, with: .color(sliver.colour.opacity(fade)))
            }
        }
        .allowsHitTesting(false)
        .opacity(reducesMotion ? 0.35 : 1)
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

/// The HUD: concentric arc rings filling the screen, with one ring segment
/// per sense and the OK pill at the centre. Sized from the frame rather than
/// a fixed 240pt box — the reference fills the screen edge to edge.
private struct LinkstartHUDContent: View {
    let elapsed: TimeInterval
    let confirmedCount: Int
    let reducesMotion: Bool

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                LinkstartHUDRings(confirmedCount: confirmedCount, elapsed: elapsed)
                okPill(side: side)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    /// The one piece of the HUD that is a control rather than decoration.
    /// Not a Button: the sequence takes no input, and a focusable control
    /// inside a full-screen overlay steals the keystroke that dismisses it.
    private func okPill(side: CGFloat) -> some View {
        let confirmed = confirmedCount >= LinkstartSequence.senses.count
        return Text(LanguageManager.shared.t("linkstart.ok"))
            .font(IslandTypography.mono(size: side * 0.075, weight: .bold))
            .tracking(side * 0.03)
            .foregroundStyle(.white)
            .padding(.horizontal, side * 0.075)
            .padding(.vertical, side * 0.028)
            .background(
                Capsule().fill(
                    confirmed
                        ? SAOGrammar.Palette.linkstartCyan1
                        : SAOGrammar.Palette.linkstartCyan3
                )
            )
            .overlay(Capsule().strokeBorder(.white.opacity(0.85), lineWidth: 2))
            .shadow(color: SAOGrammar.Palette.linkstartCyan2.opacity(0.5), radius: side * 0.03)
            .opacity(confirmed ? 1 : 0.75)
    }
}

/// The rings themselves. Each ring is a run of arc segments with gaps, drawn
/// thick enough to read as a solid band of colour from across the room, the
/// way the reference does. One ring belongs to each sense and fills in as
/// that sense is confirmed; the rest are scenery.
private struct LinkstartHUDRings: View {
    let confirmedCount: Int
    let elapsed: TimeInterval

    /// Radius fraction, thickness fraction, segment count, gap in degrees,
    /// whether the ring belongs to a sense, and its colour.
    private struct Ring {
        let radius: Double
        let thickness: Double
        let segments: Int
        let gap: Double
        let senseIndex: Int?
        let lavender: Bool
    }

    private static let rings: [Ring] = [
        Ring(radius: 0.20, thickness: 0.030, segments: 3, gap: 26, senseIndex: 0, lavender: false),
        Ring(radius: 0.27, thickness: 0.018, segments: 14, gap: 8, senseIndex: nil, lavender: true),
        Ring(radius: 0.33, thickness: 0.038, segments: 4, gap: 20, senseIndex: 1, lavender: false),
        Ring(radius: 0.41, thickness: 0.014, segments: 30, gap: 4, senseIndex: nil, lavender: false),
        Ring(radius: 0.47, thickness: 0.042, segments: 5, gap: 16, senseIndex: 2, lavender: true),
        Ring(radius: 0.55, thickness: 0.020, segments: 9, gap: 12, senseIndex: nil, lavender: false),
        Ring(radius: 0.62, thickness: 0.046, segments: 6, gap: 14, senseIndex: 3, lavender: false),
        Ring(radius: 0.71, thickness: 0.016, segments: 22, gap: 6, senseIndex: nil, lavender: true),
        Ring(radius: 0.80, thickness: 0.050, segments: 7, gap: 12, senseIndex: 4, lavender: false),
        Ring(radius: 0.90, thickness: 0.012, segments: 40, gap: 3, senseIndex: nil, lavender: false),
    ]

    var body: some View {
        Canvas { context, size in
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let side = min(size.width, size.height)
            // Slow drift, opposite directions per ring — enough to read as
            // alive, not enough to look like a loading spinner.
            let drift = elapsed * 9

            for (index, ring) in Self.rings.enumerated() {
                let radius = side * ring.radius
                let lineWidth = side * ring.thickness
                let confirmed = ring.senseIndex.map { $0 < confirmedCount } ?? true
                let base = ring.lavender
                    ? SAOGrammar.Palette.linkstartLavender1
                    : SAOGrammar.Palette.linkstartCyan1
                // Not yet confirmed is still part of the HUD: a pale version of
                // its own colour. Grey reads as broken rather than as waiting.
                let colour = confirmed ? base : base.opacity(0.28)
                let direction: Double = index.isMultiple(of: 2) ? 1 : -1
                let step = 360.0 / Double(ring.segments)

                for segment in 0..<ring.segments {
                    let start = Angle.degrees(Double(segment) * step + drift * direction + ring.gap / 2)
                    let end = Angle.degrees(Double(segment + 1) * step + drift * direction - ring.gap / 2)
                    var path = Path()
                    path.addArc(center: centre, radius: radius, startAngle: start, endAngle: end, clockwise: false)
                    context.stroke(path, with: .color(colour), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                }

                // The small blocks riding the ring — the reference is dense
                // with them, and they are what stops it reading as a target.
                if ring.segments <= 9 {
                    for marker in 0..<ring.segments {
                        let angle = Angle.degrees(Double(marker) * step + drift * direction + step / 2).radians
                        let point = CGPoint(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius)
                        let block = CGRect(
                            x: point.x - side * 0.012,
                            y: point.y - side * 0.008,
                            width: side * 0.024,
                            height: side * 0.016
                        )
                        context.fill(
                            Path(roundedRect: block, cornerRadius: side * 0.004),
                            with: .color(confirmed ? base : base.opacity(0.3))
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
