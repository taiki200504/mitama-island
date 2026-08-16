import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Finger cursor and pinch")
struct FingerCursorTests {
    @Test("An open hand reports the index tip and a wide pinch ratio")
    func readsOpenHand() throws {
        let reading = try #require(FingerCursorDetector().reading(from: hand(thumbToIndex: 0.20)))
        #expect(reading.position.x == 0.40)
        #expect(reading.pinchRatio > 0.5)
        #expect(reading.spreadRatio > 0)
    }

    /// The whole point of dividing by hand span: the same gesture at two
    /// distances from the camera has to produce the same number, or the
    /// threshold would depend on where the user happens to sit.
    @Test("Pinch ratio is unchanged when the hand is twice as far away")
    func pinchRatioIsScaleFree() throws {
        let near = try #require(FingerCursorDetector().reading(from: hand(thumbToIndex: 0.06)))
        let far = try #require(FingerCursorDetector().reading(from: hand(thumbToIndex: 0.03, scale: 0.15)))
        #expect(abs(near.pinchRatio - far.pinchRatio) < 0.0001)
    }

    @Test("A hand too small in frame is rejected")
    func rejectsTinyHand() {
        #expect(FingerCursorDetector().reading(from: hand(thumbToIndex: 0.06, scale: 0.02)) == nil)
    }

    @Test("Low confidence landmarks are rejected")
    func rejectsLowConfidence() {
        #expect(FingerCursorDetector().reading(from: hand(thumbToIndex: 0.06, confidence: 0.1)) == nil)
    }

    @Test("A held pinch begins once and ends once")
    func latchesPinch() {
        var latch = PinchLatch()
        #expect(latch.push(pinchRatio: 0.2, timestamp: 0) == nil)      // closed, still arming
        #expect(latch.push(pinchRatio: 0.2, timestamp: 0.05) == nil)   // under the hold
        #expect(latch.push(pinchRatio: 0.2, timestamp: 0.10) == .began)
        #expect(latch.push(pinchRatio: 0.2, timestamp: 0.20) == nil)   // still held, no repeat
        #expect(latch.isHolding)
        #expect(latch.push(pinchRatio: 0.60, timestamp: 0.30) == .ended)
        #expect(!latch.isHolding)
    }

    /// Between enter (0.35) and exit (0.50) nothing may change. Without the gap
    /// a resting hand emits began/ended pairs on sensor noise alone.
    @Test("Ratios inside the hysteresis band do not toggle the latch")
    func holdsThroughHysteresis() {
        var latch = PinchLatch()
        _ = latch.push(pinchRatio: 0.30, timestamp: 0)
        #expect(latch.push(pinchRatio: 0.30, timestamp: 0.1) == .began)
        #expect(latch.push(pinchRatio: 0.45, timestamp: 0.2) == nil)
        #expect(latch.isHolding)
        #expect(latch.push(pinchRatio: 0.55, timestamp: 0.3) == .ended)
    }

    /// Fingers cross during ordinary movement. A momentary close must not click.
    @Test("A pinch shorter than the hold is ignored")
    func ignoresMomentaryClose() {
        var latch = PinchLatch()
        #expect(latch.push(pinchRatio: 0.2, timestamp: 0) == nil)
        #expect(latch.push(pinchRatio: 0.9, timestamp: 0.04) == nil)
        #expect(latch.push(pinchRatio: 0.2, timestamp: 0.08) == nil)
        #expect(!latch.isHolding)
    }

    @Test("Resetting drops a held pinch without emitting")
    func resetClearsHold() {
        var latch = PinchLatch()
        _ = latch.push(pinchRatio: 0.2, timestamp: 0)
        _ = latch.push(pinchRatio: 0.2, timestamp: 0.1)
        #expect(latch.isHolding)
        latch.reset()
        #expect(!latch.isHolding)
        // The hand that appears next has to earn its own pinch.
        #expect(latch.push(pinchRatio: 0.2, timestamp: 0.2) == nil)
    }

    /// Wrist at origin, middle knuckle one span up, so span == `scale`.
    /// The thumb is placed `thumbToIndex` away from the index tip on x.
    private func hand(
        thumbToIndex: Double,
        scale: Double = 0.30,
        confidence: Double = 0.9
    ) -> HandLandmarks {
        func point(_ x: Double, _ y: Double) -> HandLandmarks.Point {
            .init(x: x, y: y, confidence: confidence)
        }
        func finger(_ x: Double, _ tipY: Double) -> HandLandmarks.Finger {
            .init(
                metacarpophalangeal: point(x, tipY * 0.4),
                proximalInterphalangeal: point(x, tipY * 0.6),
                distalInterphalangeal: point(x, tipY * 0.8),
                tip: point(x, tipY)
            )
        }
        let indexTipX = 0.40
        return .init(
            wrist: point(0.40, 0.20),
            thumb: .init(
                carpometacarpal: point(indexTipX - thumbToIndex, 0.30),
                metacarpophalangeal: point(indexTipX - thumbToIndex, 0.35),
                interphalangeal: point(indexTipX - thumbToIndex, 0.40),
                tip: point(indexTipX - thumbToIndex, 0.45)
            ),
            index: finger(indexTipX, 0.45),
            middle: .init(
                metacarpophalangeal: point(0.40, 0.20 + scale),
                proximalInterphalangeal: point(0.40, 0.20 + scale),
                distalInterphalangeal: point(0.40, 0.20 + scale),
                tip: point(0.40, 0.20 + scale)
            ),
            ring: finger(0.46, 0.45),
            little: finger(0.52, 0.45)
        )
    }
}
