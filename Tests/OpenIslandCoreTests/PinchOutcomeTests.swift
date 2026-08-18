import Foundation
import Testing
@testable import OpenIslandCore

/// カメラ層のつなぎ込みは Vision に依存して単体で回せないので、
/// 「つまむ→離す→もう一度つまむ」が2回とも決定として出ることだけを
/// ラッチの水準で押さえる。取りこぼすと2件目を選べない。
@Suite("Pinch as a repeatable pick")
struct PinchOutcomeTests {
    @Test("続けて2回つまむと2回とも決定になる")
    func pinchTwice() {
        var latch = PinchLatch()
        #expect(latch.push(pinchRatio: 0.2, timestamp: 0.00) == nil)
        #expect(latch.push(pinchRatio: 0.2, timestamp: 0.10) == .began)
        #expect(latch.push(pinchRatio: 0.8, timestamp: 0.30) == .ended)
        #expect(latch.push(pinchRatio: 0.2, timestamp: 0.40) == nil)
        #expect(latch.push(pinchRatio: 0.2, timestamp: 0.50) == .began)
    }

    /// 手が画面から出た後に残った握りを引き継ぐと、次に現れた手が
    /// 何もしていないのに決定したことになる。
    @Test("手が消えたら握りは持ち越さない")
    func handLeavingFrameClearsHold() {
        var latch = PinchLatch()
        _ = latch.push(pinchRatio: 0.2, timestamp: 0)
        _ = latch.push(pinchRatio: 0.2, timestamp: 0.1)
        #expect(latch.isHolding)
        latch.reset()
        #expect(latch.push(pinchRatio: 0.2, timestamp: 0.2) == nil)
        #expect(latch.push(pinchRatio: 0.2, timestamp: 0.31) == .began)
    }
}
