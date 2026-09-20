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
    /// 参照の地の色。白い場面を実測すると明るさ 0.916 で、純白ではない。
    static let paper = Color(hex: 0xECECEC)

    private func frame(elapsed: TimeInterval) -> some View {
        let reducesMotion = IslandMotion.reducesMotion

        return ZStack {
            // The ground: white while the tunnel runs, tinting to the HUD's
            // blue-white as the rings arrive — the reference is never a flat
            // paper white behind the interface. Dark grey during welcome/dive.
            if elapsed < LinkstartSequence.welcomeStart {
                // 参照の「白」は純白ではなく #ECECEC。純白にすると上に乗る
                // 淡い色が浮き、白い場面の明るさも参照より 0.08 上振れする。
                LinkstartView.paper
                // Dark until the light arrives: the reference opens on a black
                // screen for its first second and a half, and starting on white
                // loses the moment the whole sequence is built around.
                Color(hex: 0x111111)
                    .opacity(1 - LinkstartSequence.clamp01(
                        (elapsed - (LinkstartSequence.ignitionStart - 0.25)) / 0.35
                    ))
            } else if elapsed < LinkstartSequence.fadeStart {
                Color(hex: 0x555555)
            }

            // The speck, then the tunnel, then nothing: the white-out covers it.
            LinkstartWedgeTunnelView(elapsed: elapsed, reducesMotion: reducesMotion)
                .opacity(elapsed >= LinkstartSequence.ignitionStart
                    && elapsed < LinkstartSequence.calibrationStart ? 1 : 0)

            // The white-out between the tunnel and the interface. The dip the
            // reference has mid-way through the senses is not a flash at all —
            // it is the gap between two discs, so it draws itself.
            LinkstartView.paper
                .opacity(LinkstartSequence.flashOpacity(at: elapsed) / max(LinkstartSequence.flashPeakOpacity, 0.001))

            // 五感の確認 (5.7-8.85s): 名前を貼った円盤が通り過ぎ、確認できた
            // ものが右端に積み上がって、最後に緑になって散る。どの画面にも
            // 出す——ここは演出の本体で、出さない画面は 3 秒間ただの白になる。
            if elapsed >= LinkstartSenses.firstAppearance,
               elapsed < LinkstartSenses.tallyEnd {
                // 印が先（奥）。参照では円盤が重なる場面で印は見えない。
                LinkstartSenseTallyView(elapsed: elapsed)
                LinkstartSenseDiscsView(elapsed: elapsed)
            }

            // Language button (9.35-10.3s)
            if elapsed >= LinkstartSequence.languageSelectStart - 0.05,
               elapsed < LinkstartSequence.languageSelectStart + LinkstartSequence.languageSelectDuration {
                LinkstartLanguageButtonView(elapsed: elapsed)
            }

            // Login panel (10.8-12.5s)
            if elapsed >= LinkstartSequence.loginPanelStart - 0.05,
               elapsed < LinkstartSequence.loginPanelStart + LinkstartSequence.loginPanelDuration {
                LinkstartLoginPanelView(elapsed: elapsed)
            }

            // Confirmation dialog (12.5-13.7s)
            if elapsed >= LinkstartSequence.confirmationDialogStart - 0.1,
               elapsed < LinkstartSequence.welcomeStart + 0.1 {
                LinkstartConfirmationDialogView(elapsed: elapsed)
            }

            // Welcome text (13.8-16.6s)
            if elapsed >= LinkstartSequence.welcomeStart, elapsed < LinkstartSequence.diveStart {
                LinkstartWelcomeView(elapsed: elapsed)
            }

            // Blue dive (16.6-18.4s)
            if elapsed >= LinkstartSequence.diveStart, elapsed < LinkstartSequence.fadeStart {
                LinkstartDiveView(elapsed: elapsed, reducesMotion: reducesMotion)
            }

            // Fade to white at the end
            Color.white
                .opacity(max(0, (elapsed - LinkstartSequence.fadeStart) / LinkstartSequence.finalFadeDuration))
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
    private static let wedgeCount = 62
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
                width: (2.4 + next() * 6.6) * .pi / 180,
                lengthScale: 1.0 + next() * 1.3,
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
            let start = LinkstartSequence.ignitionStart
            let warpEnd = LinkstartSequence.flashStart
            guard elapsed >= start, elapsed < LinkstartSequence.calibrationStart else { return }

            // 0 → the slivers are a speck at the centre; 1 → they have left
            // the screen. Cubed, because the reference accelerates: barely
            // moving for the first second, gone in the last half.
            // 0 at the first speck, 1 where the tunnel ends: the reference
            // holds a still speck for two seconds before anything moves.
            let hold = LinkstartSequence.warpStart
            let travel = elapsed < hold
                // Before the tunnel: a speck that barely grows, the way the
                // reference holds an almost-empty white screen for two seconds.
                ? 0.02 * LinkstartSequence.clamp01((elapsed - start) / (hold - start))
                : 0.02 + 0.98 * pow(LinkstartSequence.clamp01((elapsed - hold) / (warpEnd - hold)), 1.35)
            let fade = elapsed <= warpEnd
                ? 1
                : max(0, 1 - (elapsed - warpEnd) / max(LinkstartSequence.flashDuration, 0.001) * 2.2)

            for sliver in Self.slivers {
                let own = max(0, travel - sliver.delay * 0.35) * sliver.speed
                // A floor, so the speck exists from the first white frame
                // instead of appearing out of nothing a second later.
                guard own > 0 || elapsed > start else { continue }
                // Tail and head both travel; the gap between them is the
                // streak, and it stretches as the thing speeds up.
                let head = min(own * 2.4, 2.6) * reach * sliver.lengthScale + 14
                // The streaks start close to the centre and stay long, so by
                // the middle of the dive the screen is colour rather than a
                // ring of slivers around a white hole.
                let tail = max(0, own - 0.7 * sliver.speed) * reach * sliver.lengthScale
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
/// 通過していく五感の円盤 (5.7-8.2s)。
///
/// 参照はここで中央のリング盤を回さない。五感の名前を貼った円盤が次々に
/// カメラの脇を通り過ぎ、通り過ぎる途中でプレートが OK へ反転する。だから
/// 画面の中心は空いていることが多く、密度は円盤が重なった時だけ上がる。
private struct LinkstartSenseDiscsView: View {
    let elapsed: TimeInterval

    /// 内円の半径を 1 としたときの、外側のリングの組み方。参照の円盤は
    /// 太い帯・細い刻み・小さなブロックが混ざっていて、線画には見えない。
    private struct Band {
        let radius: Double
        let thickness: Double
        let segments: Int
        let gap: Double
        let colour: UInt32
        let blocks: Bool
    }

    /// 内側ほど太く詰まり、外側ほど細く隙間が開く。参照の円盤は縁のほうが
    /// すかすかで、そこが白く抜けるから 1 枚でも画面を塗り潰さない。
    private static let bands: [Band] = [
        Band(radius: 1.06, thickness: 0.10, segments: 1, gap: 0, colour: 0xBCE6EC, blocks: false),
        Band(radius: 1.22, thickness: 0.22, segments: 5, gap: 14, colour: 0x1F9FD0, blocks: true),
        Band(radius: 1.40, thickness: 0.16, segments: 18, gap: 6, colour: 0x9B7BE0, blocks: false),
        Band(radius: 1.58, thickness: 0.20, segments: 4, gap: 22, colour: 0x9FC0A8, blocks: true),
        Band(radius: 1.78, thickness: 0.14, segments: 9, gap: 12, colour: 0x35B4DE, blocks: false),
        Band(radius: 2.00, thickness: 0.18, segments: 6, gap: 20, colour: 0x9B7BE0, blocks: true),
        Band(radius: 2.24, thickness: 0.10, segments: 24, gap: 6, colour: 0x1F9FD0, blocks: false),
        Band(radius: 2.50, thickness: 0.14, segments: 7, gap: 18, colour: 0x74D2E4, blocks: true),
        Band(radius: 2.80, thickness: 0.08, segments: 12, gap: 10, colour: 0x9FC0A8, blocks: false),
        Band(radius: 3.14, thickness: 0.12, segments: 5, gap: 26, colour: 0x35B4DE, blocks: true),
        Band(radius: 3.52, thickness: 0.07, segments: 20, gap: 8, colour: 0x9B7BE0, blocks: false),
        Band(radius: 3.94, thickness: 0.10, segments: 6, gap: 24, colour: 0x53C6F0, blocks: true),
    ]

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            for disc in LinkstartSenses.discs(at: elapsed) {
                var layer = context
                layer.opacity = disc.opacity
                draw(
                    disc,
                    into: &layer,
                    at: CGPoint(
                        x: centre.x + disc.offsetX * side,
                        y: centre.y + disc.offsetY * side
                    ),
                    radius: disc.radius * side
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(
        _ disc: LinkstartSenseDisc,
        into context: inout GraphicsContext,
        at point: CGPoint,
        radius: CGFloat
    ) {
        // 円盤ごとに向きをずらすと、5 枚が同じ判子に見えなくなる。
        // ゆっくり回るのは、止まっていると絵として死んで見えるため。
        let spin = Double(disc.variant) * 47 + elapsed * 5

        // 文字盤。参照の内側はベタ塗りの水色で、そこにプレートが乗る。
        context.fill(
            Path(ellipseIn: CGRect(
                x: point.x - radius, y: point.y - radius,
                width: radius * 2, height: radius * 2
            )),
            with: .color(Color(hex: 0x29AEDF))
        )

        for band in Self.bands {
            let bandRadius = radius * band.radius
            let lineWidth = radius * band.thickness
            let colour = Color(hex: band.colour)
            let direction: Double = band.segments.isMultiple(of: 2) ? 1 : -1
            let step = 360.0 / Double(max(band.segments, 1))

            for segment in 0..<max(band.segments, 1) {
                let start = Angle.degrees(Double(segment) * step + spin * direction + band.gap / 2)
                let end = Angle.degrees(Double(segment + 1) * step + spin * direction - band.gap / 2)
                var path = Path()
                path.addArc(center: point, radius: bandRadius, startAngle: start, endAngle: end, clockwise: false)
                context.stroke(
                    path,
                    with: .color(colour),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
                )
            }

            guard band.blocks else { continue }
            for marker in 0..<max(band.segments, 1) {
                let angle = Angle.degrees(Double(marker) * step + spin * direction + step / 2).radians
                let centreOfBlock = CGPoint(
                    x: point.x + cos(angle) * bandRadius,
                    y: point.y + sin(angle) * bandRadius
                )
                let block = CGRect(
                    x: centreOfBlock.x - radius * 0.11,
                    y: centreOfBlock.y - radius * 0.07,
                    width: radius * 0.22,
                    height: radius * 0.14
                )
                context.fill(Path(block), with: .color(colour))
            }
        }

        plate(disc, into: &context, at: point, radius: radius)
    }

    /// 名前の板。反転の瞬間だけ文字が消えて白く光り、そのあと OK になる。
    private func plate(
        _ disc: LinkstartSenseDisc,
        into context: inout GraphicsContext,
        at point: CGPoint,
        radius: CGFloat
    ) {
        let confirmed = disc.label == "OK"
        let plateRect = CGRect(
            x: point.x - radius * 0.80,
            y: point.y - radius * 0.22,
            width: radius * 1.60,
            height: radius * 0.44
        )
        let fill: Color = disc.label.isEmpty
            ? Color(hex: 0xF6FCFA)
            : (confirmed ? Color(hex: 0xA5E4D2) : Color(hex: 0xEAF6F2))
        context.fill(Path(plateRect), with: .color(fill))

        guard !disc.label.isEmpty else { return }
        context.draw(
            Text(disc.label)
                .font(.system(size: radius * 0.30, weight: .regular))
                .foregroundStyle(confirmed ? Color.white : Color(hex: 0x7FCFC6)),
            at: point,
            anchor: .center
        )
    }
}

/// 右端に積み上がる、確認できた五感の印 (6.3-8.85s)。
///
/// 参照では最後に 5 つが一斉に緑へ変わり、そのまま左へ散って消える。緑に
/// なるのは「五感すべて通った」の合図なので、1 つずつではなく同時に振れる。
private struct LinkstartSenseTallyView: View {
    let elapsed: TimeInterval

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            for marker in LinkstartSenses.tally(at: elapsed) {
                var layer = context
                layer.opacity = marker.opacity
                draw(
                    marker,
                    into: &layer,
                    at: CGPoint(x: marker.fractionX * size.width, y: marker.fractionY * size.height),
                    radius: marker.radius * side
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(
        _ marker: LinkstartSenseTallyMarker,
        into context: inout GraphicsContext,
        at point: CGPoint,
        radius: CGFloat
    ) {
        let shell = blend(from: 0x35B4DE, to: 0x2FD968, amount: marker.green)
        let ring = blend(from: 0xC58FE0, to: 0x50DF79, amount: marker.green)
        let core = blend(from: 0x29AEDF, to: 0x3FE070, amount: marker.green)

        for (index, ratio) in [0.98, 0.80, 0.62].enumerated() {
            var path = Path()
            path.addEllipse(in: CGRect(
                x: point.x - radius * ratio, y: point.y - radius * ratio,
                width: radius * ratio * 2, height: radius * ratio * 2
            ))
            context.stroke(
                path,
                with: .color(index.isMultiple(of: 2) ? shell : ring),
                style: StrokeStyle(lineWidth: radius * (index == 0 ? 0.20 : 0.12))
            )
        }

        context.fill(
            Path(ellipseIn: CGRect(
                x: point.x - radius * 0.44, y: point.y - radius * 0.44,
                width: radius * 0.88, height: radius * 0.88
            )),
            with: .color(core)
        )
        // 中央の横棒。参照の印は文字を持たず、この 1 本だけで「済み」を示す。
        context.fill(
            Path(CGRect(
                x: point.x - radius * 0.38, y: point.y - radius * 0.10,
                width: radius * 0.76, height: radius * 0.20
            )),
            with: .color(blend(from: 0xCFEFE8, to: 0xE6FFEE, amount: marker.green))
        )

        // 左脇の小さな四角。参照はここに 3 つ並べて列をつないでいる。
        for step in 0..<3 {
            let square = CGRect(
                x: point.x - radius * (1.45 + 0.04),
                y: point.y - radius * 0.34 + radius * 0.30 * CGFloat(step),
                width: radius * 0.16,
                height: radius * 0.16
            )
            context.fill(Path(square), with: .color(shell))
        }
    }

    private func blend(from: UInt32, to: UInt32, amount: Double) -> Color {
        func parts(_ hex: UInt32) -> (Double, Double, Double) {
            (
                Double((hex >> 16) & 0xFF) / 255,
                Double((hex >> 8) & 0xFF) / 255,
                Double(hex & 0xFF) / 255
            )
        }
        let (r1, g1, b1) = parts(from)
        let (r2, g2, b2) = parts(to)
        let t = min(max(amount, 0), 1)
        return Color(
            red: r1 + (r2 - r1) * t,
            green: g1 + (g2 - g1) * t,
            blue: b1 + (b2 - b1) * t
        )
    }
}

/// Blue "Language" button (9.8-10.8s)
private struct LinkstartLanguageButtonView: View {
    let elapsed: TimeInterval

    var body: some View {
        let progress = (elapsed - LinkstartSequence.languageSelectStart) / LinkstartSequence.languageSelectDuration
        let scale = 0.8 + 0.2 * progress

        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            Text(LanguageManager.shared.t("linkstart.language"))
                .font(.system(size: side * 0.045, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, side * 0.09)
                .padding(.vertical, side * 0.035)
                .background(RoundedRectangle(cornerRadius: side * 0.012).fill(Color(hex: 0x1379C4)))
                .scaleEffect(scale)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

/// Blue login panel with fields (10.8-12.5s)
private struct LinkstartLoginPanelView: View {
    let elapsed: TimeInterval

    var body: some View {
        let progress = (elapsed - LinkstartSequence.loginPanelStart) / LinkstartSequence.loginPanelDuration
        let passwordFill = max(0, (progress - 0.3) / 0.7)

        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let label = side * 0.032
            VStack(alignment: .leading, spacing: side * 0.035) {
                Text("Log in")
                    .font(.system(size: side * 0.05, weight: .semibold))
                    .foregroundStyle(.white)

                HStack(spacing: side * 0.03) {
                    Text("account")
                        .font(.system(size: label))
                        .foregroundStyle(.white.opacity(0.85))
                    RoundedRectangle(cornerRadius: side * 0.006)
                        .fill(Color.white.opacity(0.85))
                        .frame(height: side * 0.075)
                }

                HStack(spacing: side * 0.03) {
                    Text("password")
                        .font(.system(size: label))
                        .foregroundStyle(.white.opacity(0.85))
                    RoundedRectangle(cornerRadius: side * 0.006)
                        .fill(Color.white.opacity(0.85))
                        .frame(height: side * 0.075)
                        .overlay(alignment: .leading) {
                            // Filling in as it goes, the way the reference
                            // types the password in for you.
                            HStack(spacing: side * 0.008) {
                                ForEach(0..<10, id: \.self) { index in
                                    Circle()
                                        .fill(Color(hex: 0x1E5F96)
                                            .opacity(Double(index) < passwordFill * 10 ? 1 : 0))
                                        .frame(width: side * 0.012, height: side * 0.012)
                                }
                            }
                            .padding(.leading, side * 0.014)
                        }
                }
            }
            .padding(side * 0.06)
            .frame(width: side * 1.05)
            .background(RoundedRectangle(cornerRadius: side * 0.012).fill(Color(hex: 0x1379C4)))
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

/// Blue confirmation dialog (12.5-13.7s)
private struct LinkstartConfirmationDialogView: View {
    let elapsed: TimeInterval

    var body: some View {
        let progress = (elapsed - LinkstartSequence.confirmationDialogStart) / LinkstartSequence.confirmationDialogDuration
        let opacity = min(1.0, progress * 8)

        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            VStack(spacing: 0) {
                Text(LanguageManager.shared.t("linkstart.dialog.title"))
                    .font(.system(size: side * 0.034, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, side * 0.022)
                    .background(Color(hex: 0x11629E))

                VStack(alignment: .leading, spacing: side * 0.012) {
                    Text(LanguageManager.shared.t("linkstart.dialog.line1"))
                    Text(LanguageManager.shared.t("linkstart.dialog.line2"))
                }
                .font(.system(size: side * 0.028))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, side * 0.04)
                .padding(.vertical, side * 0.045)

                HStack(spacing: side * 0.04) {
                    ForEach(["YES", "NO"], id: \.self) { label in
                        Text(label)
                            .font(.system(size: side * 0.03, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: side * 0.14, height: side * 0.05)
                            .background(
                                RoundedRectangle(cornerRadius: side * 0.006)
                                    .fill(Color(hex: 0x3FB9E8).opacity(0.85))
                            )
                    }
                }
                .padding(.bottom, side * 0.045)
            }
            .frame(width: side * 0.88)
            .background(RoundedRectangle(cornerRadius: side * 0.01).fill(Color(hex: 0x1379C4)))
            .opacity(opacity)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

/// Welcome text display (13.8-16.6s)
private struct LinkstartWelcomeView: View {
    let elapsed: TimeInterval

    var body: some View {
        let progress = (elapsed - LinkstartSequence.welcomeStart) / LinkstartSequence.welcomeDuration
        let opacity = min(1.0, max(0.0, progress * 2))

        VStack(spacing: 0) {
            Text(LanguageManager.shared.t("linkstart.welcome.line1"))
            Text(LanguageManager.shared.t("linkstart.welcome.line2"))
        }
        .font(.system(size: 64, weight: .bold, design: .monospaced))
        .tracking(6)
        .foregroundStyle(Color.white.opacity(0.82))
        .minimumScaleFactor(0.4)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
        .opacity(opacity)
    }
}

/// Blue dive sequence (16.6-18.4s)
private struct LinkstartDiveView: View {
    let elapsed: TimeInterval
    let reducesMotion: Bool

    private static let streakCount = 220

    var body: some View {
        let progress = (elapsed - LinkstartSequence.diveStart) / LinkstartSequence.diveDuration
        let intensity = reducesMotion ? 0.3 : min(1.0, 0.45 + progress * 1.6)
        // The last fifth of the dive washes to white — the reference is
        // already white before the overlay leaves.
        let washOut = LinkstartSequence.clamp01((progress - 0.62) / 0.3) * 0.8

        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let reach = (size.width * size.width + size.height * size.height).squareRoot() / 2

            // White under everything, so the wash at the end lands on white
            // rather than on the welcome screen's grey.
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(washOut)))

            // The ground the streaks ride on, brightening as the dive runs.
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .radialGradient(
                    Gradient(colors: [
                        Color.white.opacity(0.95 * intensity),
                        Color(hex: 0x29C8F5).opacity(0.95 * intensity * (1 - washOut * 0.85)),
                        Color(hex: 0x0B6FD0).opacity(0.9 * intensity * (1 - washOut)),
                    ]),
                    center: center,
                    startRadius: 0,
                    endRadius: reach
                )
            )

            let travelled = progress * 1.5

            for index in 0..<Self.streakCount {
                let angle = Double(index) / Double(Self.streakCount) * 2 * .pi
                let offset = Double(index) / Double(Self.streakCount)
                let pace = 0.7 + 0.3 * Double(index % 3) / 3

                let depth = (offset + travelled * pace).truncatingRemainder(dividingBy: 1.0)
                let tail = max(0, depth - 0.12)

                let headRadius = min(depth * reach, reach)
                let tailRadius = max(0, tail * reach)

                guard headRadius > tailRadius else { continue }

                var path = Path()
                let halfWidth = 0.008 + 0.02 * Double(index % 4) / 4
                let a0 = angle - halfWidth
                let a1 = angle + halfWidth

                path.move(to: CGPoint(
                    x: center.x + cos(angle) * tailRadius,
                    y: center.y + sin(angle) * tailRadius
                ))
                path.addLine(to: CGPoint(
                    x: center.x + cos(a0) * headRadius,
                    y: center.y + sin(a0) * headRadius
                ))
                path.addLine(to: CGPoint(
                    x: center.x + cos(a1) * headRadius,
                    y: center.y + sin(a1) * headRadius
                ))
                path.closeSubpath()

                // White near the core, cyan further out — the streaks are the
                // light itself rather than coloured objects passing by.
                let toEdge = headRadius / reach
                let colour = Color(
                    hue: 0.53 + 0.06 * toEdge,
                    saturation: 0.15 + 0.75 * toEdge,
                    brightness: 1.0
                )
                context.fill(path, with: .color(colour.opacity((0.35 + 0.6 * intensity) * (1 - washOut))))
            }
        }
        .allowsHitTesting(false)
    }
}
