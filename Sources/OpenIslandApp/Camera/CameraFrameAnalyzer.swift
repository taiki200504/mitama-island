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
            _ = swipeDetector.push(
                isTwoFingerPose: false,
                representativeTipPosition: .init(x: 0, y: 0, confidence: 0),
                timestamp: timestamp
            )
            return
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

}
