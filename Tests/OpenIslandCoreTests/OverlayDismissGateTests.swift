import Foundation
import Testing

@testable import OpenIslandCore

@Suite("全画面の演出を閉じる猶予")
struct OverlayDismissGateTests {
    private let shown = Date(timeIntervalSince1970: 1_000_000)

    @Test("猶予 0 なら最初の一打で閉じる")
    func noGraceMeansTheFirstKeyCloses() {
        #expect(OverlayDismissGate.allowsDismiss(presentedAt: shown, now: shown, grace: 0))
    }

    @Test("猶予のあいだの入力は聞かない")
    func inputDuringTheGraceIsIgnored() {
        #expect(!OverlayDismissGate.allowsDismiss(
            presentedAt: shown, now: shown.addingTimeInterval(0.4), grace: 1.0))
        #expect(OverlayDismissGate.allowsDismiss(
            presentedAt: shown, now: shown.addingTimeInterval(1.01), grace: 1.0))
    }

    /// 全画面を奪うものの逃げ道は、何があっても 1 秒で開く。
    @Test("猶予は 1 秒で頭打ち")
    func theGraceIsCappedAtOneSecond() {
        #expect(OverlayDismissGate.allowsDismiss(
            presentedAt: shown, now: shown.addingTimeInterval(1.01), grace: 30))
        #expect(OverlayDismissGate.maximumGrace == 1.0)
    }

    @Test("負の猶予は 0 として扱う")
    func negativeGraceIsTreatedAsNone() {
        #expect(OverlayDismissGate.allowsDismiss(presentedAt: shown, now: shown, grace: -5))
    }
}
