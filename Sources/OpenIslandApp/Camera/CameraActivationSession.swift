import AVFoundation
import Foundation
import Observation
import OpenIslandCore
import os

/// Opens the camera for a few seconds, watches for the gesture, and closes it.
///
/// Short-lived on purpose. macOS lights the camera indicator for as long as the
/// device is running and no app can turn that off, so a standing capture session
/// means a green light all day. Waking on a keystroke costs one keypress and
/// buys back the light, the battery, and most of the false-positive problem —
/// a few seconds of attention is a much easier thing to filter than a whole day.
///
/// The trigger is deliberately not baked in. Today it is a hotkey; a proximity
/// signal or a standing watcher can call `begin` instead without this type
/// changing.
@MainActor
@Observable
final class CameraActivationSession {
    enum Phase: Equatable, Sendable {
        case idle
        /// Camera running, waiting for a face to match.
        case lookingForFace
        /// Face accepted (or not required) — waiting for the swipe.
        case awaitingGesture
        /// Recording the reference face for the first time.
        case enrolling
        case denied
        case unavailable
    }

    private static let logger = Logger(subsystem: "com.mitama.island", category: "camera")

    private(set) var phase: Phase = .idle

    /// Fires on the main actor when the gesture completes.
    var onGesture: (() -> Void)?
    /// Progress the UI can show. Nil clears it.
    var onStatus: ((String?) -> Void)?

    private let settings: CameraGestureSettings
    private let store: FaceReferenceStore

    private let queue = DispatchQueue(label: "app.openisland.camera", qos: .userInitiated)
    private var captureSession: AVCaptureSession?
    private var analyzer: CameraFrameAnalyzer?
    private var timeout: Task<Void, Never>?
    private var enrolmentSamples: [[Float]] = []

    init(settings: CameraGestureSettings, store: FaceReferenceStore = FaceReferenceStore()) {
        self.settings = settings
        self.store = store
    }

    var isRunning: Bool { phase != .idle && phase != .denied && phase != .unavailable }

    /// Opens the window. Called again while already open, it gives up on the
    /// camera and opens the island directly — the escape hatch for the day the
    /// face gate stops recognising its owner.
    ///
    /// Returns true when the caller should open the island itself.
    @discardableResult
    func begin() -> Bool {
        Self.logger.notice(
            "begin phase=\(String(describing: self.phase), privacy: .public) enabled=\(self.settings.isEnabled) auth=\(AVCaptureDevice.authorizationStatus(for: .video).rawValue)"
        )

        if isRunning {
            stop()
            return true
        }

        guard settings.isEnabled else { return false }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            start()
        case .notDetermined:
            // The prompt arrives on its own schedule and can land behind other
            // windows. Saying what is being waited for is the difference between
            // "nothing happened" and "answer the dialog".
            onStatus?(LanguageManager.shared.t("camera.status.requesting"))
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted {
                        self.start()
                    } else {
                        self.phase = .denied
                        self.onStatus?(LanguageManager.shared.t("camera.status.denied"))
                    }
                }
            }
            return true
        case .denied, .restricted:
            // Say so, and open the island anyway. The key was pressed three
            // times against a denied camera and the island stayed silent and
            // shut — indistinguishable from the app being broken. A shortcut
            // that does nothing and explains nothing is worse than no shortcut.
            phase = .denied
            onStatus?(LanguageManager.shared.t("camera.status.denied"))
            return true
        @unknown default:
            phase = .unavailable
        }
        return false
    }

    func stop() {
        timeout?.cancel()
        timeout = nil
        phase = .idle
        onStatus?(nil)
        enrolmentSamples = []

        let session = captureSession
        captureSession = nil
        analyzer = nil
        // Stopping blocks until the device releases, which is exactly the wrong
        // thing to do on the main actor while an animation is running.
        queue.async { session?.stopRunning() }
    }

    // MARK: - Private

    private func start() {
        let reference = store.load()
        let isEnrolling = settings.requiresFaceMatch && reference?.representativeVector == nil

        guard let session = makeCaptureSession(reference: reference, isEnrolling: isEnrolling) else {
            phase = .unavailable
            return
        }

        captureSession = session
        phase = isEnrolling ? .enrolling : (settings.requiresFaceMatch ? .lookingForFace : .awaitingGesture)
        onStatus?(statusText(for: phase))

        queue.async { session.startRunning() }

        // Enrolment needs longer than a gesture does — the user has to hold
        // still while several samples are taken.
        let seconds = isEnrolling ? max(settings.windowSeconds, 8) : settings.windowSeconds
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.finishByTimeout()
        }
    }

    /// The built-in camera, never the iPhone.
    ///
    /// `AVCaptureDevice.default(for: .video)` picks Continuity Camera when a
    /// phone is nearby, and that is a combined audio/video device: selecting it
    /// makes macOS ask for microphone access as well. This app has no
    /// `NSMicrophoneUsageDescription` — it does not want the microphone — so
    /// that request cannot be answered and the camera never opens. The symptom
    /// is a permission prompt that never resolves and no camera at all.
    private func builtInCamera() -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        ).devices.first
    }

    private func makeCaptureSession(reference: FaceReference?, isEnrolling: Bool) -> AVCaptureSession? {
        guard let device = builtInCamera() else {
            Self.logger.notice("No built-in camera found")
            return nil
        }
        Self.logger.notice("Using camera \(device.localizedName, privacy: .public)")
        guard let input = try? AVCaptureDeviceInput(device: device) else { return nil }

        let session = AVCaptureSession()
        // The smallest preset the hardware offers. Vision needs a face and a
        // hand, not a portrait, and every pixel here is power spent per frame.
        session.sessionPreset = session.canSetSessionPreset(.vga640x480) ? .vga640x480 : .low
        guard session.canAddInput(input) else { return nil }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]

        let analyzer = CameraFrameAnalyzer(
            reference: reference,
            faceThreshold: Float(settings.faceMatchThreshold),
            requiresFaceMatch: settings.requiresFaceMatch,
            isEnrolling: isEnrolling,
            onOutcome: { [weak self] outcome in
                Task { @MainActor in self?.handle(outcome) }
            }
        )
        self.analyzer = analyzer
        output.setSampleBufferDelegate(analyzer, queue: queue)

        guard session.canAddOutput(output) else { return nil }
        session.addOutput(output)
        return session
    }

    private func handle(_ outcome: CameraFrameOutcome) {
        switch outcome {
        case .idle:
            break

        case .faceMatched:
            guard phase == .lookingForFace else { return }
            phase = .awaitingGesture
            onStatus?(statusText(for: phase))

        case .faceRejected:
            guard phase == .lookingForFace else { return }
            onStatus?(LanguageManager.shared.t("camera.status.notYou"))

        case let .enrolled(sample):
            enrolmentSamples.append(sample)
            onStatus?(
                LanguageManager.shared.t("camera.status.enrolling")
                    .replacingOccurrences(of: "{count}", with: String(enrolmentSamples.count))
            )
            if enrolmentSamples.count >= 5 { finishEnrolment() }

        case .swiped:
            let fired = onGesture
            stop()
            fired?()
        }
    }

    private func finishEnrolment() {
        let samples = enrolmentSamples
        stop()
        guard !samples.isEmpty else { return }
        try? store.save(FaceReference(samples: samples))
        onStatus?(LanguageManager.shared.t("camera.status.enrolled"))
    }

    private func finishByTimeout() {
        // A half-finished enrolment is still better than none: the average of
        // three samples recognises its owner, and the alternative is asking them
        // to sit through the whole thing again.
        if phase == .enrolling, !enrolmentSamples.isEmpty {
            finishEnrolment()
            return
        }
        stop()
    }

    private func statusText(for phase: Phase) -> String? {
        switch phase {
        case .lookingForFace: LanguageManager.shared.t("camera.status.lookingForFace")
        case .awaitingGesture: LanguageManager.shared.t("camera.status.awaitingGesture")
        case .enrolling: LanguageManager.shared.t("camera.status.enrollStart")
        case .idle, .denied, .unavailable: nil
        }
    }
}
