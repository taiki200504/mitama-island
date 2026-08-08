import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Hand gesture detection")
struct HandGestureTests {
    @Test("Raised index and middle fingers are recognized")
    func recognizesTwoFingerPose() {
        #expect(TwoFingerPoseDetector().isRecognized(in: landmarks()))
    }

    @Test("A fist and an open hand are rejected")
    func rejectsNonTwoFingerPoses() {
        #expect(!TwoFingerPoseDetector().isRecognized(in: landmarks(indexExtended: false, middleExtended: false)))
        #expect(TwoFingerPoseDetector().isRecognized(in: landmarks(ringExtended: true, littleExtended: true)) == false)
    }

    /// A hand rotates as a unit in the image, so this must not depend on tip y alone.
    @Test("A twenty degree tilted hand remains recognized")
    func recognizesTiltedPose() {
        #expect(TwoFingerPoseDetector().isRecognized(in: landmarks(rotationDegrees: 20)))
    }

    @Test("Low-confidence landmarks never unlock the pose")
    func rejectsLowConfidenceLandmarks() {
        #expect(!TwoFingerPoseDetector().isRecognized(in: landmarks(confidence: 0.1)))
    }

    @Test("A deliberate downward swipe is recognized")
    func recognizesDownwardSwipe() {
        var detector = SwipeDetector()
        let fired1 = detector.push(isTwoFingerPose: true, representativeTipPosition: point(0.5, 0.8), timestamp: 0)
        #expect(!fired1)
        let fired2 = detector.push(isTwoFingerPose: true, representativeTipPosition: point(0.5, 0.7), timestamp: 0.1)
        #expect(!fired2)
        let fired3 = detector.push(isTwoFingerPose: true, representativeTipPosition: point(0.5, 0.6), timestamp: 0.2)
        #expect(fired3)
    }

    @Test("Horizontal movement is not a downward swipe")
    func rejectsHorizontalMovement() {
        var detector = SwipeDetector()
        _ = detector.push(isTwoFingerPose: true, representativeTipPosition: point(0.2, 0.7), timestamp: 0)
        _ = detector.push(isTwoFingerPose: true, representativeTipPosition: point(0.35, 0.68), timestamp: 0.1)
        let fired4 = detector.push(isTwoFingerPose: true, representativeTipPosition: point(0.5, 0.66), timestamp: 0.2)
        #expect(!fired4)
    }

    @Test("A slow lowering motion is not a swipe")
    func rejectsSlowMovement() {
        var detector = SwipeDetector()
        _ = detector.push(isTwoFingerPose: true, representativeTipPosition: point(0.5, 0.8), timestamp: 0)
        _ = detector.push(isTwoFingerPose: true, representativeTipPosition: point(0.5, 0.7), timestamp: 0.75)
        let fired5 = detector.push(isTwoFingerPose: true, representativeTipPosition: point(0.5, 0.6), timestamp: 1.5)
        #expect(!fired5)
    }

    @Test("Cooldown prevents a second panel opening")
    func enforcesCooldown() {
        var detector = SwipeDetector()
        _ = detector.push(isTwoFingerPose: true, representativeTipPosition: point(0.5, 0.8), timestamp: 0)
        _ = detector.push(isTwoFingerPose: true, representativeTipPosition: point(0.5, 0.7), timestamp: 0.1)
        let fired6 = detector.push(isTwoFingerPose: true, representativeTipPosition: point(0.5, 0.6), timestamp: 0.2)
        #expect(fired6)

        _ = detector.push(isTwoFingerPose: true, representativeTipPosition: point(0.5, 0.8), timestamp: 0.3)
        _ = detector.push(isTwoFingerPose: true, representativeTipPosition: point(0.5, 0.7), timestamp: 0.4)
        let fired7 = detector.push(isTwoFingerPose: true, representativeTipPosition: point(0.5, 0.6), timestamp: 0.5)
        #expect(!fired7)
    }

    private func landmarks(
        indexExtended: Bool = true,
        middleExtended: Bool = true,
        ringExtended: Bool = false,
        littleExtended: Bool = false,
        confidence: Double = 0.9,
        rotationDegrees: Double = 0
    ) -> HandLandmarks {
        func rotated(_ x: Double, _ y: Double) -> HandLandmarks.Point {
            let radians = rotationDegrees * .pi / 180
            let cosine = cos(radians)
            let sine = sin(radians)
            return point(0.5 + x * cosine - y * sine, 0.2 + x * sine + y * cosine, confidence: confidence)
        }
        func finger(_ x: Double, _ baseY: Double, extended: Bool) -> HandLandmarks.Finger {
            let tipY = baseY + (extended ? 0.25 : 0.025)
            return .init(
                metacarpophalangeal: rotated(x, baseY),
                proximalInterphalangeal: rotated(x, baseY + (extended ? 0.08 : 0.015)),
                distalInterphalangeal: rotated(x, baseY + (extended ? 0.16 : 0.02)),
                tip: rotated(x, tipY)
            )
        }

        return .init(
            wrist: rotated(0, 0),
            thumb: .init(
                carpometacarpal: rotated(-0.12, 0.02),
                metacarpophalangeal: rotated(-0.16, 0.07),
                interphalangeal: rotated(-0.2, 0.1),
                tip: rotated(-0.23, 0.12)
            ),
            index: finger(-0.07, 0.1, extended: indexExtended),
            middle: finger(0, 0.12, extended: middleExtended),
            ring: finger(0.07, 0.1, extended: ringExtended),
            little: finger(0.13, 0.08, extended: littleExtended)
        )
    }

    private func point(_ x: Double, _ y: Double, confidence: Double = 0.9) -> HandLandmarks.Point {
        .init(x: x, y: y, confidence: confidence)
    }
}
