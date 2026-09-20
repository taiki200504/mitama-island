import Foundation

public extension LinkstartSense {
    /// 円盤のプレートに焼かれている文字。参照映像の綴りをそのまま写している
    /// ——"sight" だけ小文字なのは元がそう書いているからで、直さない。
    /// ローカライズもしない: これは UI の文言ではなく、再現している画の一部。
    var plateLabel: String {
        switch self {
        case .touch: "Touch"
        case .sight: "sight"
        case .hearing: "Hearing"
        case .taste: "Taste"
        case .smell: "Smell"
        }
    }
}

/// 通過していく円盤 1 枚の、ある瞬間の姿。
///
/// 位置は画面中心からのずれで、単位は短辺。短辺基準にしておくと、ノートの
/// 画面でも 6K でも同じ構図になる。
public struct LinkstartSenseDisc: Equatable, Sendable {
    public let sense: LinkstartSense
    /// プレートに出る文字。反転の瞬間だけ空（参照では板が一度白く光る）。
    public let label: String
    public let offsetX: Double
    public let offsetY: Double
    /// 文字盤（内円）の半径 ÷ 短辺。外側のリングはこの何倍かで描く。
    public let radius: Double
    public let opacity: Double
    /// 円盤ごとに絵を変えるための番号。乱数は使わない——ハーネスが任意の
    /// 時刻を固定して描くので、同じ時刻は必ず同じ絵でなければならない。
    public let variant: Int
}

/// 確認の印。中央で生まれ、確認が済むと右端の自分の段へ移って積み上がる。
public struct LinkstartSenseTallyMarker: Equatable, Sendable {
    public let sense: LinkstartSense
    /// 画面の幅・高さに対する位置。右端に貼り付く印なので、短辺ではなく
    /// 画面そのものを基準にする。
    public let fractionX: Double
    public let fractionY: Double
    /// 半径 ÷ 短辺。
    public let radius: Double
    public let opacity: Double
    /// 0 = 青いまま、1 = 緑。五感が揃ったところで一斉に緑へ振れる。
    public let green: Double
}

/// 五感の確認（5.5〜8.85 秒）を、経過時間の純関数として持つ。
///
/// 参照映像はここで中央のリング盤を回さない。順番はこうなっている:
///
/// 1. 小さな印が画面の中央に生まれ、数を増やしながら少し育つ
/// 2. 五感の名前を貼った大きな円盤がカットインし、膨らみながら脇へ抜ける
/// 3. プレートが一瞬白くなって OK に反転し、その印が右端の段へ移る
/// 4. 五つ揃うと右端の五つが一斉に緑になり、左へ散って消える
///
/// 時刻はすべて参照映像から測った値。本人の音源（19.04 秒）と同じ素材から
/// 測っているので、ここを合わせると音とも合う。
public enum LinkstartSenses: Sendable {
    /// 円盤 1 枚の一生。`directionX/Y` は画面外へ抜けていく向き、
    /// `scatterX/Y` は最後に緑の印が散っていく向き。
    public struct Beat: Equatable, Sendable {
        public let sense: LinkstartSense
        /// 大きな円盤がカットインする時刻。参照はここで 1 フレーム（0.04 秒）
        /// のうちに画面の三分の一が埋まる——ゆっくり育ててはいけない。
        public let appears: TimeInterval
        public let confirms: TimeInterval
        public let leaves: TimeInterval
        public let directionX: Double
        public let directionY: Double
        public let scatterX: Double
        public let scatterY: Double
        /// カットインした瞬間の文字盤の半径 ÷ 短辺。参照の円盤は 1 枚ずつ
        /// 大きさが違い、揃えると重なった時の密度が参照から外れる。
        public let prime: Double
        /// 抜けるまでに何倍になるか。
        public let growth: Double
    }

    /// 参照映像から 0.04 秒刻み（＝1 フレーム）で測った時刻。
    public static let beats: [Beat] = [
        Beat(sense: .touch, appears: 5.72, confirms: 6.02, leaves: 6.58,
             directionX: -1.0, directionY: 0.42, scatterX: -1.8, scatterY: 0.05,
             prime: 0.3, growth: 2.4),
        Beat(sense: .sight, appears: 5.95, confirms: 6.38, leaves: 6.8,
             directionX: 0.98, directionY: -0.34, scatterX: -1.45, scatterY: -0.12,
             prime: 0.34, growth: 2.2),
        Beat(sense: .hearing, appears: 6.95, confirms: 7.37, leaves: 7.78,
             directionX: -1.0, directionY: 0.3, scatterX: -1.35, scatterY: 0.02,
             prime: 0.26, growth: 2.3),
        Beat(sense: .taste, appears: 7.3, confirms: 7.65, leaves: 8.02,
             directionX: 0.52, directionY: -0.92, scatterX: -1.5, scatterY: 0.16,
             prime: 0.28, growth: 2.3),
        Beat(sense: .smell, appears: 7.58, confirms: 7.87, leaves: 8.1,
             directionX: -0.88, directionY: 0.58, scatterX: -1.3, scatterY: -0.06,
             prime: 0.28, growth: 2.3),
    ]

    /// 五感ではない、画を埋めるためだけの円盤。参照は 7.5〜8.0 のあたりで
    /// 右に「名前のない OK」をもう 1 枚流している。五感は 5 つしかないので、
    /// これをどれかに割り当てると、同じ円盤が縮んで戻ることになる。
    /// 印の数には入れない。
    static let decoys: [Beat] = [
        Beat(sense: .taste, appears: 7.56, confirms: 7.56, leaves: 7.98,
             directionX: 0.96, directionY: 0.14, scatterX: 0, scatterY: 0,
             prime: 0.15, growth: 1.6),
    ]

    /// 中心は半径に比例して軸の外へ流れる（＝軸から外れた球を通り過ぎる）。
    static let centreDrift = 1.15
    /// 入りは 1 フレーム、抜けは長め。6.85 と 8.1 の「ほぼ白」の谷は、この
    /// 抜け際と退場時刻だけで作る（白いフラッシュを被せて偽装しない）。
    static let discFadeIn: TimeInterval = 0.04
    static let discFadeOut: TimeInterval = 0.10

    /// 反転の瞬間、文字が消えて板だけになる時間。
    static let plateBlankDuration: TimeInterval = 0.09

    /// 印は大きな円盤より先に、中央に生まれる。参照の 5.50 秒に見えている
    /// 小さな 2 つは、触覚と視覚の印。
    static let markerLead: TimeInterval = 0.25
    static let markerGrowth: TimeInterval = 0.30
    /// 反転してから右端の段へ移るまで。
    static let markerTravelDelay: TimeInterval = 0.03
    static let markerTravelDuration: TimeInterval = 0.30
    /// 右端の列。上から下へ 5 段。
    static let tallyColumnX = 0.905
    static let tallySlotTop = 0.10
    static let tallySlotStep = 0.20
    static let tallyRadius = 0.105

    /// 五つ揃ったところで一斉に緑へ。
    public static let greenStart: TimeInterval = 8.28
    static let greenRamp: TimeInterval = 0.12
    /// 緑の印が散り始め、消え終わる時刻。
    public static let scatterStart: TimeInterval = 8.60
    public static let tallyEnd: TimeInterval = 8.85

    /// 何かが描かれ始める時刻。ビューが描き始める目印。
    public static var firstAppearance: TimeInterval { beats[0].appears - markerLead }

    /// いま画面にいる円盤。奥（小さい）から手前（大きい）の順に返すので、
    /// 呼ぶ側はそのまま描けば重なりが正しくなる。
    public static func discs(at elapsed: TimeInterval) -> [LinkstartSenseDisc] {
        let named = beats.enumerated().compactMap { index, beat in
            disc(beat, at: elapsed, variant: index)
        }
        let unnamed = decoys.enumerated().compactMap { index, beat in
            disc(beat, at: elapsed, variant: index + beats.count)
        }
        return (named + unnamed).sorted { $0.radius < $1.radius }
    }

    private static func disc(_ beat: Beat, at elapsed: TimeInterval, variant: Int) -> LinkstartSenseDisc? {
        guard elapsed >= beat.appears, elapsed < beat.leaves else { return nil }
        let progress = (elapsed - beat.appears) / (beat.leaves - beat.appears)
        let radius = beat.prime * pow(beat.growth, progress)
        let drift = radius * centreDrift
        let label: String
        if elapsed < beat.confirms {
            label = beat.sense.plateLabel
        } else if elapsed < beat.confirms + plateBlankDuration {
            label = ""
        } else {
            label = okLabel
        }
        let opacity = min(
            LinkstartSequence.clamp01((elapsed - beat.appears) / discFadeIn),
            LinkstartSequence.clamp01((beat.leaves - elapsed) / discFadeOut)
        )
        return LinkstartSenseDisc(
            sense: beat.sense,
            label: label,
            offsetX: beat.directionX * drift,
            offsetY: beat.directionY * drift,
            radius: radius,
            opacity: opacity,
            variant: variant
        )
    }

    /// いま出ている確認の印。散り終わったあとは空。
    public static func tally(at elapsed: TimeInterval) -> [LinkstartSenseTallyMarker] {
        guard elapsed < tallyEnd else { return [] }
        let green = LinkstartSequence.clamp01((elapsed - greenStart) / greenRamp)
        let scatter = LinkstartSequence.clamp01(
            (elapsed - scatterStart) / max(tallyEnd - scatterStart, 0.001)
        )
        // 散り始めはゆっくり、最後に加速する。止まっていたものが弾ける動き。
        let eased = scatter * scatter

        return beats.enumerated().compactMap { index, beat -> LinkstartSenseTallyMarker? in
            let born = beat.appears - markerLead
            guard elapsed >= born else { return nil }
            let grown = LinkstartSequence.clamp01((elapsed - born) / markerGrowth)
            // 中央から右端の段へ。移動は confirm の直後、0.45 秒かけて。
            let travelStart = beat.confirms + markerTravelDelay
            let travel = LinkstartSequence.clamp01((elapsed - travelStart) / markerTravelDuration)
            // 出だしと着地をなめらかに。等速だと「飛ばされた」ように見える。
            let easedTravel = travel * travel * (3 - 2 * travel)
            let slotY = tallySlotTop + tallySlotStep * Double(index)
            let x = 0.5 + (tallyColumnX - 0.5) * easedTravel
            let y = 0.5 + (slotY - 0.5) * easedTravel
            return LinkstartSenseTallyMarker(
                sense: beat.sense,
                fractionX: x + beat.scatterX * eased,
                fractionY: y + beat.scatterY * eased,
                radius: tallyRadius * (0.25 + 0.75 * grown) * (1 + 0.55 * eased),
                opacity: grown * (1 - eased),
                green: green
            )
        }
    }

    /// 反転し終わった五感の数。音のキューと位相はここから決まる。
    public static func confirmedCount(at elapsed: TimeInterval) -> Int {
        beats.count { elapsed >= $0.confirms }
    }

    /// 反転後にプレートへ出る文字。参照は言語に関係なくこの 2 文字。
    static let okLabel = "OK"
}
