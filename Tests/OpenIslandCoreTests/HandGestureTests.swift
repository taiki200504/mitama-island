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
        #expect(nil == fired1)
        let fired2 = detector.push(isTwoFingerPose: true, representativeTipPosition: point(0.5, 0.7), timestamp: 0.1)
        #expect(nil == fired2)
        let fired3 = detector.push(isTwoFingerPose: true, representativeTipPosition: point(0.5, 0.6), timestamp: 0.2)
        #expect(.down == fired3)
    }

    @Test("Horizontal movement is not a downward swipe")
    func rejectsHorizontalMovement() {
        var detector = SwipeDetector()
        _ = detector.push(isTwoFingerPose: true, representativeTipPosition: point(0.2, 0.7), timestamp: 0)
        _ = detector.push(isTwoFingerPose: true, representativeTipPosition: point(0.35, 0.68), timestamp: 0.1)
        let fired4 = detector.push(isTwoFingerPose: true, representativeTipPosition: point(0.5, 0.66), timestamp: 0.2)
        #expect(nil == fired4)
    }

    @Test("A slow lowering motion is not a swipe")
    func rejectsSlowMovement() {
        var detector = SwipeDetector()
        _ = detector.push(isTwoFingerPose: true, representativeTipPosition: point(0.5, 0.8), timestamp: 0)
        _ = detector.push(isTwoFingerPose: true, representativeTipPosition: point(0.5, 0.7), timestamp: 0.75)
        let fired5 = detector.push(isTwoFingerPose: true, representativeTipPosition: point(0.5, 0.6), timestamp: 1.5)
        #expect(nil == fired5)
    }

    @Test("Cooldown prevents a second panel opening")
    func enforcesCooldown() {
        var detector = SwipeDetector()
        _ = detector.push(isTwoFingerPose: true, representativeTipPosition: point(0.5, 0.8), timestamp: 0)
        _ = detector.push(isTwoFingerPose: true, representativeTipPosition: point(0.5, 0.7), timestamp: 0.1)
        let fired6 = detector.push(isTwoFingerPose: true, representativeTipPosition: point(0.5, 0.6), timestamp: 0.2)
        #expect(.down == fired6)

        _ = detector.push(isTwoFingerPose: true, representativeTipPosition: point(0.5, 0.8), timestamp: 0.3)
        _ = detector.push(isTwoFingerPose: true, representativeTipPosition: point(0.5, 0.7), timestamp: 0.4)
        let fired7 = detector.push(isTwoFingerPose: true, representativeTipPosition: point(0.5, 0.6), timestamp: 0.5)
        #expect(nil == fired7)
    }

    // MARK: - Open palm

    @Test("Every finger extended is read as an open palm")
    func recognizesOpenPalm() {
        #expect(OpenPalmDetector().isRecognized(in: landmarks(ringExtended: true, littleExtended: true)))
    }

    /// The two gestures share the camera, so neither may answer for the other.
    @Test("The two-finger pose is not an open palm, and the reverse holds")
    func openPalmAndTwoFingerPoseAreExclusive() {
        let twoFingers = landmarks()
        let openPalm = landmarks(ringExtended: true, littleExtended: true)

        #expect(!OpenPalmDetector().isRecognized(in: twoFingers))
        #expect(!TwoFingerPoseDetector().isRecognized(in: openPalm))
    }

    @Test("A fist is not an open palm")
    func rejectsFistAsOpenPalm() {
        let fist = landmarks(indexExtended: false, middleExtended: false)
        #expect(!OpenPalmDetector().isRecognized(in: fist))
    }

    @Test("A tilted open palm is still an open palm")
    func recognizesTiltedOpenPalm() {
        #expect(
            OpenPalmDetector().isRecognized(
                in: landmarks(ringExtended: true, littleExtended: true, rotationDegrees: 20)
            )
        )
    }

    @Test("Low-confidence landmarks never unlock the open palm")
    func rejectsLowConfidenceOpenPalm() {
        #expect(
            !OpenPalmDetector().isRecognized(
                in: landmarks(ringExtended: true, littleExtended: true, confidence: 0.1)
            )
        )
    }

    // MARK: - Holding a pose

    @Test("A pose held briefly does not fire")
    func holdBelowThresholdDoesNotFire() {
        var detector = PoseHoldDetector()
        let atStart = detector.push(isPosed: true, timestamp: 0)
        #expect(atStart == false)
        let tooSoon = detector.push(isPosed: true, timestamp: 0.3)
        #expect(tooSoon == false)
    }

    @Test("A pose held long enough fires exactly once")
    func holdFiresOnceWhenSustained() {
        var detector = PoseHoldDetector()
        let atStart = detector.push(isPosed: true, timestamp: 0)
        #expect(atStart == false)
        let held = detector.push(isPosed: true, timestamp: 0.7)
        #expect(held)
        // The hand is still up on the next frame; that is not a second answer.
        let stillUp = detector.push(isPosed: true, timestamp: 0.8)
        #expect(stillUp == false)
    }

    /// Dropping the hand halfway is how you change your mind.
    @Test("Losing the pose restarts the hold")
    func losingThePoseRestartsTheHold() {
        var detector = PoseHoldDetector()
        let atStart = detector.push(isPosed: true, timestamp: 0)
        #expect(atStart == false)
        let dropped = detector.push(isPosed: false, timestamp: 0.3)
        #expect(dropped == false)
        let raisedAgain = detector.push(isPosed: true, timestamp: 0.4)
        #expect(raisedAgain == false)
        // 0.9 is 0.9s after the first frame but only 0.5s into this hold.
        let notYet = detector.push(isPosed: true, timestamp: 0.9)
        #expect(notYet == false)
        let held = detector.push(isPosed: true, timestamp: 1.1)
        #expect(held)
    }

    @Test("A raised hand cannot fire twice inside the cooldown")
    func cooldownSuppressesRepeatFiring() {
        var detector = PoseHoldDetector()
        _ = detector.push(isPosed: true, timestamp: 0)
        let firstFire = detector.push(isPosed: true, timestamp: 0.7)
        #expect(firstFire)

        let insideCooldown = detector.push(isPosed: true, timestamp: 1.5)
        #expect(insideCooldown == false)
        let stillInsideCooldown = detector.push(isPosed: true, timestamp: 2.5)
        #expect(stillInsideCooldown == false)

        // Leaving the cooldown is not itself an answer: the hold has to be
        // earned again, or a hand left up would fire on a timer.
        let cooldownJustEnded = detector.push(isPosed: true, timestamp: 3.3)
        #expect(cooldownJustEnded == false)
        let heldAgain = detector.push(isPosed: true, timestamp: 4.0)
        #expect(heldAgain)
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

    /// Closing the panel is the opposite motion, and it must not be mistaken
    /// for the one that opens it.
    @Test("An upward swipe is reported as up, not down")
    func recognizesUpwardSwipe() {
        var detector = SwipeDetector()
        let fired8 = detector.push(isTwoFingerPose: true, representativeTipPosition: point(0.5, 0.6), timestamp: 0)
        #expect(nil == fired8)
        let fired9 = detector.push(isTwoFingerPose: true, representativeTipPosition: point(0.5, 0.7), timestamp: 0.1)
        #expect(nil == fired9)
        let fired10 = detector.push(isTwoFingerPose: true, representativeTipPosition: point(0.5, 0.8), timestamp: 0.2)
        #expect(.up == fired10)
    }
}
