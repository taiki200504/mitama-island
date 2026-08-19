import AVFoundation
import Foundation
import OpenIslandCore
import Vision

/// What one camera frame amounted to.
enum CameraFrameOutcome: Equatable, Sendable {
    /// Nothing to report. Most frames are this.
    case idle
    /// The gesture completed, in this direction.
    case swiped(SwipeDirection)
    /// An open hand was held up long enough to mean it.
    case palmHeld
    /// Thumb and index closed and stayed closed. The hands-free "pick this".
    case pinched
    /// The hand has moved to somewhere new. Half of pointing at a row and
    /// picking it — without this the pinch has nothing to pick.
    case pointing(FingerCursorReading)
}

/// Runs Vision over capture frames and turns them into outcomes.
///
/// Lives entirely on the capture queue. `AVCaptureVideoDataOutput` guarantees
/// its delegate is called serially on the queue it was given, so the mutable
/// state here is confined by that contract rather than by a lock — a lock would
/// be contended on every frame for no benefit.
///
/// The classic `VNImageRequestHandler` is used rather than the newer async
/// Vision API: this runs synchronously on a frame that is already in hand, and
/// spawning a task per frame to await a result would queue work faster than the
/// camera delivers it.
final class CameraFrameAnalyzer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    /// Called on the capture queue.
    private let onOutcome: @Sendable (CameraFrameOutcome) -> Void

    private let poseDetector = TwoFingerPoseDetector()
    private var swipeDetector = SwipeDetector()
    private let palmDetector = OpenPalmDetector()
    private var palmHoldDetector = PoseHoldDetector()
    private let cursorDetector = FingerCursorDetector()
    /// Where the hand was when it was last worth telling anyone about.
    private var lastReportedAim: Double?
    /// A hand is never perfectly still. Reporting every frame would put a
    /// tremor onto the list; this is smaller than the distance between two
    /// rows and larger than a hand holding position.
    private static let aimReportingStep = 0.012
    private var pinchLatch = PinchLatch()

    init(onOutcome: @escaping @Sendable (CameraFrameOutcome) -> Void) {
        self.onOutcome = onOutcome
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // The camera is mirrored, so Vision's left is the user's right. It makes
        // no difference to a vertical swipe, and correcting it would cost an
        // orientation pass on every frame.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        detectGesture(with: handler, timestamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds)
    }

    // MARK: - Gesture

    private func detectGesture(with handler: VNImageRequestHandler, timestamp: TimeInterval) {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 1
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first,
              let landmarks = Self.landmarks(from: observation) else {
            // A frame with no hand breaks the run, which is what stops two
            // separate downward motions from being stitched into one swipe.
            breakRun(at: timestamp)
            return
        }

        // Both gestures read the same frame. They cannot answer for each other:
        // the swipe needs the ring and little fingers folded, the palm needs
        // them extended.
        if palmHoldDetector.push(isPosed: palmDetector.isRecognized(in: landmarks), timestamp: timestamp) {
            onOutcome(.palmHeld)
        }

        // Pinch is read before the swipe. Closing the thumb onto the index
        // folds the hand out of the two-finger pose on its way, so letting the
        // swipe detector see those frames first would spend the pinch as a
        // half-finished swipe.
        if let reading = cursorDetector.reading(from: landmarks) {
            if pinchLatch.push(pinchRatio: reading.pinchRatio, timestamp: timestamp) == .began {
                onOutcome(.pinched)
            }
            reportPointing(reading)
        }

        guard let tip = poseDetector.representativeTipPosition(in: landmarks) else {
            _ = swipeDetector.push(
                isTwoFingerPose: false,
                representativeTipPosition: .init(x: 0, y: 0, confidence: 0),
                timestamp: timestamp
            )
            return
        }

        if let direction = swipeDetector.push(
            isTwoFingerPose: true,
            representativeTipPosition: tip,
            timestamp: timestamp
        ) {
            onOutcome(.swiped(direction))
        }
    }

    /// Tells both detectors that the hand left the frame.
    private func breakRun(at timestamp: TimeInterval) {
        _ = swipeDetector.push(
            isTwoFingerPose: false,
            representativeTipPosition: .init(x: 0, y: 0, confidence: 0),
            timestamp: timestamp
        )
        _ = palmHoldDetector.push(isPosed: false, timestamp: timestamp)
        // A held pinch must not survive the hand leaving frame, or the next
        // hand to appear inherits a pinch it never made.
        pinchLatch.reset()
        lastReportedAim = nil
    }

    private static func landmarks(from observation: VNHumanHandPoseObservation) -> HandLandmarks? {
        func point(_ joint: VNHumanHandPoseObservation.JointName) -> HandLandmarks.Point? {
            guard let recognized = try? observation.recognizedPoint(joint) else { return nil }
            return .init(
                x: Double(recognized.location.x),
                y: Double(recognized.location.y),
                confidence: Double(recognized.confidence)
            )
        }

        guard let wrist = point(.wrist),
              let thumbCMC = point(.thumbCMC), let thumbMP = point(.thumbMP),
              let thumbIP = point(.thumbIP), let thumbTip = point(.thumbTip),
              let indexMCP = point(.indexMCP), let indexPIP = point(.indexPIP),
              let indexDIP = point(.indexDIP), let indexTip = point(.indexTip),
              let middleMCP = point(.middleMCP), let middlePIP = point(.middlePIP),
              let middleDIP = point(.middleDIP), let middleTip = point(.middleTip),
              let ringMCP = point(.ringMCP), let ringPIP = point(.ringPIP),
              let ringDIP = point(.ringDIP), let ringTip = point(.ringTip),
              let littleMCP = point(.littleMCP), let littlePIP = point(.littlePIP),
              let littleDIP = point(.littleDIP), let littleTip = point(.littleTip)
        else { return nil }

        return HandLandmarks(
            wrist: wrist,
            thumb: .init(
                carpometacarpal: thumbCMC,
                metacarpophalangeal: thumbMP,
                interphalangeal: thumbIP,
                tip: thumbTip
            ),
            index: .init(
                metacarpophalangeal: indexMCP,
                proximalInterphalangeal: indexPIP,
                distalInterphalangeal: indexDIP,
                tip: indexTip
            ),
            middle: .init(
                metacarpophalangeal: middleMCP,
                proximalInterphalangeal: middlePIP,
                distalInterphalangeal: middleDIP,
                tip: middleTip
            ),
            ring: .init(
                metacarpophalangeal: ringMCP,
                proximalInterphalangeal: ringPIP,
                distalInterphalangeal: ringDIP,
                tip: ringTip
            ),
            little: .init(
                metacarpophalangeal: littleMCP,
                proximalInterphalangeal: littlePIP,
                distalInterphalangeal: littleDIP,
                tip: littleTip
            )
        )
    }

    private func reportPointing(_ reading: FingerCursorReading) {
        if let lastReportedAim, abs(reading.position.y - lastReportedAim) < Self.aimReportingStep {
            return
        }
        lastReportedAim = reading.position.y
        onOutcome(.pointing(reading))
    }
}
