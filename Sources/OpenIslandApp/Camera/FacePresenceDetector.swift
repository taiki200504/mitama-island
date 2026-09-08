import AVFoundation
import Foundation
import Vision

/// Watches camera frames for the presence of a face — not who it is, not
/// whether it is looking, just that someone is in front of the screen.
///
/// Used only to swap a glyph in the unlock greeting; this detects presence,
/// not identity, and confirms nothing on its own. Lives entirely on the
/// capture queue, same discipline as `CameraFrameAnalyzer`:
/// `AVCaptureVideoDataOutput` calls its delegate serially on the queue it was
/// given, so the one flag this tracks needs no lock.
final class FacePresenceDetector: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    /// Called at most once, on the capture queue, the first time a face is seen.
    private let onFaceSeen: @Sendable () -> Void
    private var hasReported = false

    init(onFaceSeen: @escaping @Sendable () -> Void) {
        self.onFaceSeen = onFaceSeen
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !hasReported, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        let request = VNDetectFaceRectanglesRequest()
        guard (try? handler.perform([request])) != nil, let results = request.results, !results.isEmpty else {
            return
        }
        hasReported = true
        onFaceSeen()
    }
}
