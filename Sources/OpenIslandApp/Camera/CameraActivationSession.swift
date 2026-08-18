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
        /// Camera running, waiting for the swipe.
        case awaitingGesture
        case denied
        case unavailable
    }

    private static let logger = Logger(subsystem: "com.mitama.island", category: "camera")

    private(set) var phase: Phase = .idle

    /// Fires on the main actor when the gesture completes, with its direction.
    var onGesture: ((SwipeDirection) -> Void)?
    /// Fires when an open hand was held up. The camera stays on.
    var onPalmHeld: (() -> Void)?
    /// Fires when thumb and index closed. "Pick the thing in front of me."
    /// The camera stays on so a second pick can follow without re-summoning.
    var onPinch: (() -> Void)?
    /// Progress the UI can show. Nil clears it.
    var onStatus: ((String?) -> Void)?

    private let settings: CameraGestureSettings

    private let queue = DispatchQueue(label: "app.openisland.camera", qos: .userInitiated)
    private var captureSession: AVCaptureSession?
    private var analyzer: CameraFrameAnalyzer?
    private var timeout: Task<Void, Never>?
    /// True while the camera is held open by a waiting card rather than by a keypress.
    private var keepsCameraOpen = false
    /// So the explanation is given once per run of refusals rather than on
    /// every card that arrives.
    private var hasSaidCameraIsNotAllowed = false

    init(settings: CameraGestureSettings) {
        self.settings = settings
    }

    var isRunning: Bool { phase != .idle && phase != .denied && phase != .unavailable }

    /// Opens the window. Called again while already open, it gives up on the
    /// camera and opens the island directly.
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
            AVCaptureDevice.requestAccess(for: .video) { @Sendable [weak self] granted in
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

    /// Keeps the camera open for as long as a card is waiting to be answered,
    /// so a raised hand is enough — no key to press first.
    ///
    /// Unlike `begin()` there is no timeout: the thing that closes this is the
    /// card being answered or going away. The green light therefore means
    /// exactly one thing — something is waiting on you.
    func beginSustained() {
        guard settings.isEnabled, settings.answersByPalm else { return }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            // Never ask for the camera on this path. A permission dialog that
            // appears because a card arrived, rather than because a key was
            // pressed, has no explanation attached to it.
            //
            // Say why once. Silence here reads as "the setting does nothing",
            // and the way out — press the key, answer the dialog — is not
            // something anyone would guess.
            if !hasSaidCameraIsNotAllowed {
                hasSaidCameraIsNotAllowed = true
                onStatus?(LanguageManager.shared.t("camera.status.palmNeedsPermission"))
            }
            return
        }
        hasSaidCameraIsNotAllowed = false

        keepsCameraOpen = true
        guard !isRunning else {
            // Already open from a keypress, and that window has a clock on it.
            // Leaving the clock running would close the camera out from under a
            // card that is still waiting.
            timeout?.cancel()
            timeout = nil
            return
        }
        Self.logger.notice("Sustained camera opening")
        start()
    }

    func endSustained() {
        guard keepsCameraOpen else { return }
        keepsCameraOpen = false
        Self.logger.notice("Sustained camera closing")
        stop()
    }

    func stop() {
        keepsCameraOpen = false
        timeout?.cancel()
        timeout = nil
        phase = .idle
        onStatus?(nil)

        let session = captureSession
        captureSession = nil
        analyzer = nil
        // Stopping blocks until the device releases, which is exactly the wrong
        // thing to do on the main actor while an animation is running.
        queue.async { session?.stopRunning() }
    }

    // MARK: - Private

    private func start() {
        guard let session = makeCaptureSession() else {
            phase = .unavailable
            return
        }

        captureSession = session
        phase = .awaitingGesture
        onStatus?(statusText(for: phase))

        queue.async { session.startRunning() }

        // A sustained camera is closed by the card going away, not by a clock.
        guard !keepsCameraOpen else { return }

        let seconds = settings.windowSeconds
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

    private func makeCaptureSession() -> AVCaptureSession? {
        guard let device = builtInCamera() else {
            Self.logger.notice("No built-in camera found")
            return nil
        }
        Self.logger.notice("Using camera \(device.localizedName, privacy: .public)")
        guard let input = try? AVCaptureDeviceInput(device: device) else { return nil }

        let session = AVCaptureSession()
        // The smallest preset the hardware offers. Vision needs a hand, not a
        // portrait, and every pixel here is power spent per frame.
        session.sessionPreset = session.canSetSessionPreset(.vga640x480) ? .vga640x480 : .low
        guard session.canAddInput(input) else { return nil }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]

        let analyzer = CameraFrameAnalyzer { [weak self] outcome in
            Task { @MainActor in self?.handle(outcome) }
        }
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

        case let .swiped(direction):
            let fired = onGesture
            stop()
            fired?(direction)

        case .palmHeld:
            // The camera stays on: the answer is spoken next, and the card may
            // still be there afterwards.
            onPalmHeld?()

        case .pinched:
            // Unlike a swipe, picking is repeatable: you take one thing, then
            // the next. Stopping here would make the second pick cost another
            // summon, which is slower than reaching for the keyboard.
            onPinch?()
        }
    }

    private func finishByTimeout() {
        // Say why the camera went out. Turning on and off with no explanation is
        // the same silence as never turning on.
        Self.logger.notice("Window closed in phase=\(String(describing: self.phase), privacy: .public)")
        let wasWaiting = phase == .awaitingGesture
        stop()
        if wasWaiting { onStatus?(LanguageManager.shared.t("camera.status.timedOutOnGesture")) }
    }

    private func statusText(for phase: Phase) -> String? {
        switch phase {
        case .awaitingGesture: LanguageManager.shared.t("camera.status.awaitingGesture")
        case .idle, .denied, .unavailable: nil
        }
    }
}
