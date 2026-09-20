import Foundation
import Testing

@testable import OpenIslandCore

/// 参照映像（本人の音源と同じ素材、19.04 秒）を 0.04〜0.25 秒刻みで見て
/// 取った観測を、そのまま期待値にしている。ここが緑なら、画は参照と同じ
/// 時刻に同じものを出している。
@Suite("五感の円盤")
struct LinkstartSensesTests {
    /// 参照のその時刻に、プレートに見えている文字。
    @Test(
        "参照で見えている文字が、その時刻に出ている",
        arguments: [
            (5.80, ["Touch"]),
            (6.00, ["Touch", "sight"]),
            (6.25, ["OK", "sight"]),
            (6.50, ["OK", "OK"]),
            (7.25, ["Hearing"]),
            (7.50, ["OK", "Taste"]),
            (8.12, [String]()),
        ]
    )
    func platesMatchTheReference(at elapsed: TimeInterval, labels: [String]) {
        let seen = LinkstartSenses.discs(at: elapsed).map(\.label).sorted()
        #expect(seen == labels.sorted(), Comment(rawValue: "\(elapsed)s の円盤: \(seen)"))
    }

    @Test("反転の瞬間だけ、板から文字が消える")
    func plateGoesBlankOnTheFlip() {
        let touch = LinkstartSenses.beats[0]
        #expect(label(of: .touch, at: touch.confirms - 0.01) == "Touch")
        #expect(label(of: .touch, at: touch.confirms + 0.01) == "")
        #expect(label(of: .touch, at: touch.confirms + LinkstartSenses.plateBlankDuration + 0.01) == "OK")
    }

    /// 参照はここで画面がほとんど白くなる。円盤が抜けた結果であって、
    /// 白いフラッシュを被せているのではない。
    @Test("円盤のあいだに白の谷がある", arguments: [6.88, 8.15])
    func theGapsBetweenDiscsAreEmpty(at elapsed: TimeInterval) {
        let ink = LinkstartSenses.discs(at: elapsed)
            .reduce(0.0) { $0 + $1.opacity * $1.radius }
        #expect(ink < 0.05, Comment(rawValue: "\(elapsed)s に円盤が残っている"))
    }

    @Test("確認済みの印が、右端に 1 つずつ積み上がる")
    func marksStackUpAtTheRightEdge() {
        func docked(_ elapsed: TimeInterval) -> Int {
            LinkstartSenses.tally(at: elapsed).count { $0.fractionX > 0.85 }
        }
        // 参照の実測: 7.00 で 2 個、8.00 で 4 個、8.25 で 5 個。
        #expect(docked(7.00) == 2)
        #expect(docked(8.00) == 4)
        #expect(docked(8.25) == 5)
    }

    @Test("印は中央で生まれて右端へ移る")
    func marksAreBornInTheMiddle() {
        let touch = LinkstartSenses.beats[0]
        let born = touch.appears - LinkstartSenses.markerLead
        let first = try? #require(LinkstartSenses.tally(at: born + 0.02).first)
        #expect((first?.fractionX ?? 0) < 0.55)
        #expect((first?.radius ?? 1) < LinkstartSenses.tallyRadius * 0.5)
    }

    @Test("五つ揃ってから緑になり、散って消える")
    func theMarksTurnGreenTogetherThenScatter() {
        #expect(LinkstartSenses.tally(at: LinkstartSenses.greenStart - 0.05).allSatisfy { $0.green == 0 })
        #expect(LinkstartSenses.tally(at: 8.45).allSatisfy { $0.green == 1 })
        #expect(LinkstartSenses.tally(at: 8.45).count == 5)
        // 散り始めると薄くなり、終われば何も残らない。
        let scattering = LinkstartSenses.tally(at: 8.78)
        #expect(scattering.allSatisfy { $0.opacity < 1 })
        #expect(LinkstartSenses.tally(at: LinkstartSenses.tallyEnd).isEmpty)
    }

    @Test("円盤は奥から手前の順に返る")
    func discsComeBackBackToFront() {
        let radii = LinkstartSenses.discs(at: 6.2).map(\.radius)
        #expect(radii == radii.sorted())
    }

    /// 時刻を固定して描くハーネスがあるので、同じ時刻は必ず同じ絵になること。
    @Test("同じ時刻なら必ず同じ答え")
    func theSameMomentAlwaysLooksTheSame() {
        #expect(LinkstartSenses.discs(at: 7.3) == LinkstartSenses.discs(at: 7.3))
        #expect(LinkstartSenses.tally(at: 7.3) == LinkstartSenses.tally(at: 7.3))
    }

    @Test("円盤は膨らむだけで、縮んで戻らない")
    func discsOnlyEverGrow() {
        // 名前のない円盤も味覚の名前を借りているので、sense ではなく
        // variant で拾う。
        for (index, beat) in LinkstartSenses.beats.enumerated() {
            var previous = 0.0
            for elapsed in stride(from: beat.appears, to: beat.leaves, by: 0.01) {
                let radius = LinkstartSenses.discs(at: elapsed)
                    .first { $0.variant == index }?.radius ?? previous
                #expect(radius >= previous - 1e-9)
                previous = radius
            }
        }
    }

    /// 表と `LinkstartSequence` の時間割が食い違うと、音と画がずれる。
    @Test("段取りの時間割と噛み合っている")
    func theTableAgreesWithTheTimeline() {
        #expect(LinkstartSenses.firstAppearance > LinkstartSequence.flashStart)
        #expect(LinkstartSenses.discs(at: LinkstartSequence.sensesCheckStart).isEmpty)
        #expect(abs(LinkstartSenses.tallyEnd
            - (LinkstartSequence.sensesCheckStart + LinkstartSequence.sensesCheckDuration)) < 0.01)
        #expect(LinkstartSenses.tallyEnd < LinkstartSequence.languageSelectStart - 0.4)
        #expect(LinkstartSenses.beats.map(\.sense) == LinkstartSequence.senses)
    }

    private func label(of sense: LinkstartSense, at elapsed: TimeInterval) -> String? {
        LinkstartSenses.discs(at: elapsed).first { $0.sense == sense }?.label
    }
}
