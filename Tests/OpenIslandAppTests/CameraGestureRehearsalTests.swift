import Foundation
import Testing

@testable import OpenIslandApp

@MainActor
@Suite("ジェスチャの練習")
struct CameraGestureRehearsalTests {
    private typealias Rehearsal = CameraGestureRehearsal
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func entry(_ sighting: Rehearsal.Sighting, _ offset: TimeInterval) -> Rehearsal.Entry {
        Rehearsal.Entry(id: UUID(), sighting: sighting, at: start.addingTimeInterval(offset))
    }

    @Test("新しいものが先頭に来る")
    func theNewestComesFirst() {
        var entries = Rehearsal.recording(.swipeDown, at: start, into: [])
        entries = Rehearsal.recording(.palm, at: start.addingTimeInterval(2), into: entries)
        #expect(entries.map(\.sighting) == [.palm, .swipeDown])
    }

    /// 指差しは 1 秒に何度も来る。そのまま積むと一覧が指差しだけで埋まり、
    /// 「二本指が通ったか」を見に来た人が何も読めなくなる。
    @Test("同じものが続けて来たら 1 件にまとめる")
    func repeatsCollapseIntoOne() {
        var entries = Rehearsal.recording(.pointing, at: start, into: [])
        let id = entries[0].id
        entries = Rehearsal.recording(.pointing, at: start.addingTimeInterval(0.2), into: entries)
        entries = Rehearsal.recording(.pointing, at: start.addingTimeInterval(0.4), into: entries)
        #expect(entries.count == 1)
        // 同じ行が時刻だけ新しくなる（id が変わると一覧が毎回作り直される）。
        #expect(entries[0].id == id)
        #expect(entries[0].at == start.addingTimeInterval(0.4))
    }

    @Test("間が空けば別の 1 件として並ぶ")
    func aPauseMakesANewEntry() {
        var entries = Rehearsal.recording(.pointing, at: start, into: [])
        entries = Rehearsal.recording(
            .pointing,
            at: start.addingTimeInterval(Rehearsal.coalescingInterval + 0.1),
            into: entries
        )
        #expect(entries.count == 2)
    }

    @Test("古いものは落ちる")
    func oldSightingsFallOff() {
        let old = entry(.palm, -(Rehearsal.window + 1))
        let entries = Rehearsal.recording(.swipeDown, at: start, into: [old])
        #expect(entries.map(\.sighting) == [.swipeDown])
    }

    @Test("画面に残す数を超えない")
    func theListStaysShort() {
        var entries: [Rehearsal.Entry] = []
        for step in 0..<(Rehearsal.visibleLimit + 5) {
            entries = Rehearsal.recording(
                .swipeDown,
                at: start.addingTimeInterval(Double(step) * (Rehearsal.coalescingInterval + 0.1)),
                into: entries
            )
        }
        #expect(entries.count == Rehearsal.visibleLimit)
    }

    /// 走っていない間に認識が届いても積まない——練習を止めたあとに
    /// 最後の 1 フレームが遅れて来ることがある。
    @Test("走っていなければ何も積まない")
    func nothingIsRecordedWhileStopped() {
        let rehearsal = Rehearsal()
        rehearsal.record(.palm)
        #expect(rehearsal.entries.isEmpty)
    }

    @Test("止めると走っていない状態に戻る")
    func stoppingClearsTheRunningFlag() async {
        let rehearsal = Rehearsal()
        rehearsal.start(seconds: 60) {}
        #expect(rehearsal.isRunning)
        rehearsal.record(.swipeDown)
        #expect(rehearsal.entries.count == 1)
        rehearsal.stop()
        #expect(!rehearsal.isRunning)
    }

    @Test("五つの見分けにそれぞれ文言がある")
    func everySightingHasAString() {
        let keys = Set(Rehearsal.Sighting.allCases.map(\.labelKey))
        #expect(keys.count == Rehearsal.Sighting.allCases.count)
        for key in keys {
            #expect(LanguageManager.shared.t(key) != key, Comment(rawValue: "\(key) の訳が無い"))
        }
    }
}
