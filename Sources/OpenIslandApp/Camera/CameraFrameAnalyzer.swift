import AVFoundation
import Foundation
import OpenIslandCore
import Vision

/// What one camera frame amounted to.
enum CameraFrameOutcome: Equatable, Sendable {
    /// Nothing to report. Most frames are this.
    case idle
    /// A face was seen and matched the enrolled reference.
    case faceMatched
    /// A face was seen and did not match.
    case faceRejected
    /// One enrolment sample was captured.
    case enrolled(sample: [Float])
    /// The gesture completed.
    case swiped
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

    private let reference: FaceReference?
    private let faceThreshold: Float
    private let requiresFaceMatch: Bool
    private let isEnrolling: Bool

    /// Once the face has matched, stop paying for face work every frame. The
    /// window is a few seconds long; nobody swaps places inside it.
    private var faceSettled = false
    private var enrolledSamples = 0

    /// Enough samples to average out one badly lit frame, few enough that
    /// enrolment finishes before the window does.
    private static let enrolmentSampleTarget = 5
    /// Faces are looked for at this interval, hands on every frame. Face work
    /// costs several times more and the answer does not change frame to frame.
    private static let faceCheckStride = 5
    private var frameIndex = 0

    init(
        reference: FaceReference?,
        faceThreshold: Float,
        requiresFaceMatch: Bool,
        isEnrolling: Bool,
        onOutcome: @escaping @Sendable (CameraFrameOutcome) -> Void
    ) {
        self.reference = reference
        self.faceThreshold = faceThreshold
        self.requiresFaceMatch = requiresFaceMatch
        self.isEnrolling = isEnrolling
        self.onOutcome = onOutcome
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frameIndex += 1

        // The camera is mirrored, so Vision's left is the user's right. It makes
        // no difference to a vertical swipe, and correcting it would cost an
        // orientation pass on every frame.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        if isEnrolling {
            enrol(with: handler)
            return
        }

        if requiresFaceMatch, !faceSettled, frameIndex % Self.faceCheckStride == 1 {
            switch matchFace(with: handler) {
            case .some(true):
                faceSettled = true
                onOutcome(.faceMatched)
            case .some(false):
                onOutcome(.faceRejected)
            case nil:
                break  // No face in frame yet. Not a rejection — keep looking.
            }
        }

        guard !requiresFaceMatch || faceSettled else { return }
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

        if swipeDetector.push(isTwoFingerPose: true, representativeTipPosition: tip, timestamp: timestamp) {
            onOutcome(.swiped)
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

    // MARK: - Face

    /// Nil means no face was found — distinct from a face that did not match,
    /// because only the second one should tell the user anything.
    private func matchFace(with handler: VNImageRequestHandler) -> Bool? {
        guard let reference, let vector = faceVector(with: handler) else { return nil }
        return reference.isLikelyMatch(vector, threshold: faceThreshold)
    }

    private func enrol(with handler: VNImageRequestHandler) {
        guard enrolledSamples < Self.enrolmentSampleTarget,
              frameIndex % Self.faceCheckStride == 1,
              let vector = faceVector(with: handler) else { return }
        enrolledSamples += 1
        onOutcome(.enrolled(sample: vector))
    }

    /// A face's feature print, or nil when no face is in frame.
    ///
    /// This is a general-purpose image descriptor, not a face embedding — Apple
    /// ships no public face recognition. Restricting it to the face rectangle is
    /// what makes it discriminate between people at all, and it is still weak:
    /// good enough to keep the island from opening for the room, not good enough
    /// to guard anything that matters.
    private func faceVector(with handler: VNImageRequestHandler) -> [Float]? {
        let faceRequest = VNDetectFaceRectanglesRequest()
        guard (try? handler.perform([faceRequest])) != nil,
              let face = faceRequest.results?.max(by: { $0.boundingBox.height < $1.boundingBox.height })
        else { return nil }

        let printRequest = VNGenerateImageFeaturePrintRequest()
        printRequest.regionOfInterest = face.boundingBox
        guard (try? handler.perform([printRequest])) != nil,
              let observation = printRequest.results?.first,
              observation.elementType == .float
        else { return nil }

        return observation.data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
    }
}
