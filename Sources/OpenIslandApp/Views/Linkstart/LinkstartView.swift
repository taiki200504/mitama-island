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
    /// 「視差を減らす」をこの描画に限って決め打ちするための口。既定は nil で
    /// システム設定に従う。**オフスクリーンで測るときは必ず渡す**: CI の
    /// マシンはこの設定が入っていて、同じ時刻でもトンネルが 0.35 の薄さで
    /// 描かれ、参照との比較が環境で変わってしまう。
    var reducesMotionOverride: Bool?

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
        let reducesMotion = reducesMotionOverride ?? IslandMotion.reducesMotion

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
                    // 参照は 1.4 秒でまだ明るさ 0.40、1.6 秒で真っ白。
                    // 前へ寄せすぎると、暗い場面が短くなって軽く見える。
                    .opacity(1 - LinkstartSequence.clamp01(
                        (elapsed - (LinkstartSequence.ignitionStart - 0.10)) / 0.25
                    ))
            } else if elapsed < LinkstartSequence.fadeStart {
                // 参照の灰は #808080 ちょうど。0x555555 だと暗すぎて、
                // 文字を白く置く羽目になり明暗が逆になる。
                Color(hex: 0x808080)
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
                LinkstartSenseTallyView(elapsed: elapsed, reducesMotion: reducesMotion)
                LinkstartSenseDiscsView(elapsed: elapsed, reducesMotion: reducesMotion)
            }

            // Language button (9.35-10.3s)
            if elapsed >= LinkstartSequence.languageSelectStart - 0.05,
               elapsed < LinkstartSequence.languageSelectStart + LinkstartSequence.languageSelectDuration + 0.15 {
                LinkstartLanguageButtonView(elapsed: elapsed)
            }

            // サインイン (10.4-11.95s)。参照は 11.9 でもまだパネルが出ていて、
            // 白い間は 12.0 の直前まで短い。
            if elapsed >= LinkstartSequence.loginPanelStart - 0.05,
               elapsed < LinkstartSequence.loginPanelStart + LinkstartSequence.loginPanelDuration + 0.25 {
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
    /// 参照のトンネルは原色だけではない。白・黒・灰の楔が混ざっていて、
    /// それが画面全体の彩度を下げ、明暗の幅を作っている（全部を原色に
    /// すると彩度が参照の 1.5 倍になる）。
    private static let palette: [Color] = [
        Color(hex: 0xE8253B),   // red
        Color(hex: 0xFFFFFF),   // white
        Color(hex: 0x00C8E0),   // cyan
        Color(hex: 0x111111),   // black
        Color(hex: 0xE81DC8),   // magenta
        Color(hex: 0xF0D000),   // yellow
        Color(hex: 0x9A9A9A),   // grey
        Color(hex: 0x14C850),   // green
        Color(hex: 0xFFFFFF),   // white
        Color(hex: 0x7B3BE8),   // violet
        Color(hex: 0x111111),   // black
        Color(hex: 0xFF7A00),   // orange
        Color(hex: 0x1F49C8),   // deep blue
        Color(hex: 0x808080),   // grey
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
            // 参照の 1.6〜2.9 秒は彩度 0.000 の白で、**本当に何も無い**。
            // 火花が出るのは 2.95 秒から。そこから 3.5 秒までは小さいまま。
            let sparkStart = hold - 0.55
            let travel = elapsed < hold
                ? 0.055 * LinkstartSequence.clamp01((elapsed - sparkStart) / (hold - sparkStart))
                // 参照は動き出してすぐ画面が埋まる。1.35 乗だと出だしが
                // 遅すぎて、3.6 秒でまだ白いままだった。
                : 0.055 + 0.945 * pow(LinkstartSequence.clamp01((elapsed - hold) / (warpEnd - hold)), 1.0)
            let fade = elapsed <= warpEnd
                ? 1
                : max(0, 1 - (elapsed - warpEnd) / max(LinkstartSequence.flashDuration, 0.001) * 2.2)

            for sliver in Self.slivers {
                let own = max(0, travel - sliver.delay * 0.35) * sliver.speed
                guard own > 0 else { continue }
                // Tail and head both travel; the gap between them is the
                // streak, and it stretches as the thing speeds up.
                let head = min(own * 2.4, 2.6) * reach * sliver.lengthScale + 14
                // The streaks start close to the centre and stay long, so by
                // the middle of the dive the screen is colour rather than a
                // ring of slivers around a white hole.
                // 尾を長く引く。短いと、参照がまだ色で埋まっている 4.8 秒に
                // こちらは白くなってしまう。
                let tail = max(0, own - 1.15 * sliver.speed) * reach * sliver.lengthScale
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
    /// 動きを減らす設定のとき、円盤は出入りするが画面を横切らない。
    let reducesMotion: Bool

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
            for disc in LinkstartSenses.discs(at: elapsed, holding: reducesMotion) {
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
        let spin = Double(disc.variant) * 47 + (reducesMotion ? 0 : elapsed * 5)

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
    let reducesMotion: Bool

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            for marker in LinkstartSenses.tally(at: elapsed, holding: reducesMotion) {
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

/// 言語の選択 (9.35-10.3s)。
///
/// 参照では画面の左寄り・やや上に濃い青の「Language」が出て、少し遅れて
/// その右からシアンの「▶ 日本語」が滑り出す。中央に 1 個だけ置くと、
/// 位置も動きも参照と別物になる。位置と大きさは参照の実測値:
/// ボタンは x 0.175–0.486 / y 0.294–0.392、選択は x 0.455–0.758。
private struct LinkstartLanguageButtonView: View {
    let elapsed: TimeInterval

    var body: some View {
        let progress = LinkstartSequence.clamp01(
            (elapsed - LinkstartSequence.languageSelectStart) / LinkstartSequence.languageSelectDuration
        )
        // 選択が滑り出すのは、ボタンが出てひと呼吸おいてから。
        let slide = LinkstartSequence.clamp01((progress - 0.34) / 0.22)

        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let side = min(width, height)
            let buttonHeight = side * 0.097
            let buttonWidth = side * 0.553
            let buttonCentre = CGPoint(x: width * 0.331, y: height * 0.343)

            ZStack(alignment: .topLeading) {
                // 選択のほう。ボタンの裏から出てくるので先に描く。
                Text("▶  " + LanguageManager.shared.t("linkstart.language.value"))
                    .font(.system(size: side * 0.042, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: side * 0.545, height: buttonHeight, alignment: .leading)
                    .padding(.leading, side * 0.055)
                    .background(
                        RoundedRectangle(cornerRadius: side * 0.014)
                            .fill(Color(hex: 0x2FC3F0))
                    )
                    .opacity(slide)
                    .position(
                        x: buttonCentre.x + buttonWidth * (0.28 + 0.62 * slide),
                        y: buttonCentre.y + side * 0.045
                    )

                Text(LanguageManager.shared.t("linkstart.language"))
                    .font(.system(size: side * 0.046, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: buttonWidth, height: buttonHeight)
                    .background(
                        RoundedRectangle(cornerRadius: side * 0.014)
                            .fill(Color(hex: 0x1478D2))
                    )
                    .shadow(color: .black.opacity(0.18), radius: side * 0.012, y: side * 0.006)
                    .position(buttonCentre)
                    .opacity(LinkstartSequence.clamp01(
                        (elapsed - (LinkstartSequence.languageSelectStart - 0.09)) / 0.12
                    ))
                    .opacity(LinkstartSequence.clamp01(
                        (LinkstartSequence.languageSelectStart + LinkstartSequence.languageSelectDuration
                            + 0.14 - elapsed) / 0.14
                    ))
            }
            .frame(width: width, height: height)
        }
    }
}

/// サインインのパネル (10.4-11.8s)。
///
/// 参照の実測: パネルは画面の中央、幅 0.875・高さ 0.325（短辺basis）。
/// 左に「Log in_::」、右にラベルを**上に置いた**白いフィールドが 2 段。
/// 文字はアスタリスクで、下の段はその場で打たれていく。
private struct LinkstartLoginPanelView: View {
    let elapsed: TimeInterval

    var body: some View {
        let progress = LinkstartSequence.clamp01(
            (elapsed - LinkstartSequence.loginPanelStart) / LinkstartSequence.loginPanelDuration
        )
        // 上の段は最初から埋まっていて、下の段が打たれていく。
        let typed = Int((LinkstartSequence.clamp01((progress - 0.25) / 0.45) * 5).rounded(.down))

        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let fieldWidth = side * 0.343
            HStack(alignment: .center, spacing: side * 0.06) {
                Text("Log in_::")
                    .font(.system(size: side * 0.058, weight: .regular))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: side * 0.028) {
                    field(":account", value: "*********", width: fieldWidth, side: side)
                    field(":password", value: String(repeating: "*", count: typed),
                          width: fieldWidth, side: side)
                }
            }
            .padding(.horizontal, side * 0.055)
            .frame(width: side * 0.875, height: side * 0.325)
            .background(
                RoundedRectangle(cornerRadius: side * 0.018)
                    .fill(Color(hex: 0x1379C4))
            )
            .shadow(color: .black.opacity(0.22), radius: side * 0.016, y: side * 0.008)
            .opacity(min(
                LinkstartSequence.clamp01(progress / 0.10),
                // 引き際は秒で測る——progress は 1 で頭打ちなので、
                // そこから引くと永遠に 1 のままになる。
                LinkstartSequence.clamp01(
                    (LinkstartSequence.loginPanelStart + LinkstartSequence.loginPanelDuration
                        + 0.25 - elapsed) / 0.26
                )
            ))
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    /// ラベルはフィールドの**上**。参照は横に並べていない。
    private func field(_ label: String, value: String, width: CGFloat, side: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: side * 0.008) {
            Text(label)
                .font(.system(size: side * 0.036))
                .foregroundStyle(.white)
            Text(value)
                .font(.system(size: side * 0.034, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(hex: 0x333333))
                .frame(width: width, height: side * 0.050, alignment: .leading)
                .padding(.leading, side * 0.010)
                .background(Color.white)
        }
    }
}

/// 確認のダイアログ (12.0-13.55s)。
///
/// 参照の実測（画面に対する割合）: 題の丸帯は x 0.325–0.677 / y 0.211–0.292、
/// 本体は x 0.166–0.836 / y 0.328–0.831。題は本体から離れて上に浮いていて、
/// くっついた見出し帯ではない。本体には白い縁があり、文中に名前のチップ、
/// 下に YES / NO の小さな丸帯が 2 つ（x 0.319–0.422 と 0.578–0.680）。
private struct LinkstartConfirmationDialogView: View {
    let elapsed: TimeInterval

    var body: some View {
        let progress = LinkstartSequence.clamp01(
            (elapsed - LinkstartSequence.confirmationDialogStart) / LinkstartSequence.confirmationDialogDuration
        )
        let opacity = LinkstartSequence.clamp01(progress * 8)

        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            VStack(spacing: side * 0.036) {
                Text(LanguageManager.shared.t("linkstart.dialog.title"))
                    .font(.system(size: side * 0.040, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: side * 0.626, height: side * 0.081)
                    .background(
                        RoundedRectangle(cornerRadius: side * 0.040)
                            .fill(Color(hex: 0x1478D2))
                            .overlay(
                                RoundedRectangle(cornerRadius: side * 0.040)
                                    .strokeBorder(.white.opacity(0.9), lineWidth: max(1, side * 0.003))
                            )
                    )

                VStack(spacing: side * 0.030) {
                    VStack(spacing: side * 0.012) {
                        Text(LanguageManager.shared.t("linkstart.dialog.line1"))
                        Text(LanguageManager.shared.t("linkstart.dialog.line2"))
                    }
                    .font(.system(size: side * 0.042))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                    Text(LanguageManager.shared.t("linkstart.dialog.profile"))
                        .font(.system(size: side * 0.042, weight: .bold, design: .monospaced))
                        .tracking(side * 0.010)
                        .foregroundStyle(.white)
                        .frame(width: side * 0.414, height: side * 0.058)
                        .background(Color(hex: 0x35C6EF))

                    HStack(spacing: side * 0.155) {
                        ForEach(["YES", "NO"], id: \.self) { label in
                            Text(label)
                                .font(.system(size: side * 0.034, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: side * 0.183, height: side * 0.044)
                                .background(
                                    RoundedRectangle(cornerRadius: side * 0.022)
                                        .fill(Color(hex: 0x35C6EF))
                                )
                        }
                    }
                }
                .padding(.vertical, side * 0.050)
                .frame(width: side * 1.191, height: side * 0.503)
                .background(
                    RoundedRectangle(cornerRadius: side * 0.030)
                        .fill(Color(hex: 0x1379C4))
                        .overlay(
                            RoundedRectangle(cornerRadius: side * 0.030)
                                .strokeBorder(.white.opacity(0.9), lineWidth: max(1, side * 0.004))
                        )
                )
            }
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

        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            VStack(spacing: side * 0.012) {
                Text(LanguageManager.shared.t("linkstart.welcome.line1"))
                Text(LanguageManager.shared.t("linkstart.welcome.line2"))
            }
            // 参照の文字は画面の高さの 1 割ほどの背丈がある。固定 64pt だと
            // 画面が大きいほど小さく見えて、灰色の面ばかりになる。
            .font(.system(size: side * 0.145, weight: .bold, design: .monospaced))
            .tracking(side * 0.012)
        // 参照は #808080 の地に #2B2C2C の文字。白抜きではない。
        .foregroundStyle(Color(hex: 0x2B2C2C))
            .minimumScaleFactor(0.4)
            .multilineTextAlignment(.center)
            .padding(.horizontal, side * 0.06)
            .opacity(opacity)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

/// Blue dive sequence (16.6-18.4s)
private struct LinkstartDiveView: View {
    let elapsed: TimeInterval
    let reducesMotion: Bool

    private static let streakCount = 320

    /// 地の色。芯にいくほど白い。
    private static func groundColour(at radius: Double) -> Color {
        let anchors: [(Double, Double, Double)] = [
            (1.00, 1.00, 1.00),     // 芯
            (0.16, 0.78, 0.96),     // 中ほど
            (0.04, 0.31, 0.66),     // 縁
        ]
        let t = min(max(radius, 0), 1) * 2
        let lower = min(Int(t), 1)
        let f = t - Double(lower)
        let a = anchors[lower], b = anchors[lower + 1]
        return Color(
            red: a.0 + (b.0 - a.0) * f,
            green: a.1 + (b.1 - a.1) * f,
            blue: a.2 + (b.2 - a.2) * f
        )
    }

    /// 芯の白から縁の青へ。`Color(hue:saturation:brightness:)` は描く側の
    /// 色空間に左右され、CI では同じ指定でも彩度が 0.2 ほど変わった。
    /// ほかの場所と同じ sRGB の直値で混ぜる。
    private static func rayColour(toEdge: Double, tint: Int) -> Color {
        let anchors: [(Double, Double, Double)] = [
            (1.00, 1.00, 1.00),     // 芯
            (0.44, 0.88, 1.00),     // 中ほどの水色
            (0.10, 0.40, 0.88),     // 縁の青
        ]
        let t = min(max(toEdge, 0), 1) * 2
        let lower = min(Int(t), 1)
        let f = t - Double(lower)
        let a = anchors[lower], b = anchors[lower + 1]
        // 1 本ごとに少しだけ色味を変える。全部同じだと帯に見える。
        let shift = 0.04 * Double(tint - 1)
        return Color(
            red: min(max(a.0 + (b.0 - a.0) * f - shift, 0), 1),
            green: min(max(a.1 + (b.1 - a.1) * f, 0), 1),
            blue: min(max(a.2 + (b.2 - a.2) * f + shift, 0), 1)
        )
    }

    var body: some View {
        let progress = (elapsed - LinkstartSequence.diveStart) / LinkstartSequence.diveDuration
        let intensity = reducesMotion ? 0.3 : min(1.0, 0.45 + progress * 1.6)
        // 白へ抜けるのは最後のひと息だけ。18.2 秒の参照はまだ彩度 0.39 の
        // 青で、ここを早く白くすると色が死ぬ。
        let washOut = LinkstartSequence.clamp01((progress - 0.74) / 0.22) * 0.55

        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let reach = (size.width * size.width + size.height * size.height).squareRoot() / 2

            // 筋が乗る地。芯は小さく強く、外は濃い青。グラデーションで
            // 塗っていたが、同じ指定でも CI の描画と手元とで彩度が 0.25 も
            // 違った（画面いっぱいの塗りほど差が出る）。環境を当てにしない
            // よう、実色の同心円を外から内へ重ねて同じ絵を作る。
            let ringCount = 28
            for step in 0..<ringCount {
                let outer = 1 - Double(step) / Double(ringCount)
                let colour = Self.groundColour(at: outer)
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: center.x - reach * outer, y: center.y - reach * outer,
                        width: reach * outer * 2, height: reach * outer * 2
                    )),
                    with: .color(colour.opacity(0.95 * intensity))
                )
            }

            let travelled = progress * 1.5

            for index in 0..<Self.streakCount {
                let angle = Double(index) / Double(Self.streakCount) * 2 * .pi
                // 深さは角度と相関させない。index をそのまま使うと、角度と
                // 深さが一緒に増えて渦巻きになり、参照の「四方へ伸びる光」に
                // ならない（実際そうなっていた）。
                let offset = Double((index &* 2_654_435_761) % 9_973) / 9_973
                let pace = 0.7 + 0.3 * Double(index % 3) / 3

                let depth = (offset + travelled * pace).truncatingRemainder(dividingBy: 1.0)
                // 長い筋。0.12 は点に近く、参照の「中心から縁へ伸びる光」に
                // ならない。
                let tail = max(0, depth - 0.45)

                let headRadius = min(depth * reach, reach)
                let tailRadius = max(0, tail * reach)

                guard headRadius > tailRadius else { continue }

                var path = Path()
                // 近づくほど太く見える。等幅だと縁がすかすかで、参照の
                // 「光が横を走り抜ける」感じにならない。
                let halfWidth = (0.008 + 0.02 * Double(index % 4) / 4) * (0.6 + depth * 2.2)
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
                let colour = Self.rayColour(toEdge: toEdge, tint: index % 3)
                // 縁ほど濃く出す。中央付近は地の光に溶けていてよいが、
                // 画面の端は筋が立っていないと参照の密度にならない。
                let weight = 0.35 + 0.85 * toEdge
                context.fill(path, with: .color(colour.opacity((0.30 + 0.75 * intensity) * weight)))
            }

            // 最後に白へ抜ける。地と筋を描いたあとに白をかぶせる——下に
            // 敷くと、上の塗りに隠れて効かない。
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(.white.opacity(washOut))
            )
        }
        .allowsHitTesting(false)
    }
}
