import AVFoundation
import Foundation
import Observation
import OpenIslandCore
import os
import Speech

/// Opens the microphone for a few seconds, listens for an answer, and closes it.
///
/// The same shape as `CameraActivationSession`, for the same reason: a standing
/// microphone is worse than a standing camera — there is no indicator most
/// people watch, and the thing being captured is speech. This opens on a
/// keypress and only when a card is actually waiting for an answer, so the
/// microphone is shut in every other moment of the day.
///
/// Recognition is on-device. Nothing spoken here leaves the machine.
@MainActor
@Observable
final class VoiceCommandSession {
    enum Phase: Equatable, Sendable {
        case idle
        /// Waiting for the model to be installed before anything can be heard.
        case preparing
        case listening
        case denied
        case unavailable
    }

    private static let logger = Logger(subsystem: "com.mitama.island", category: "voice")

    private(set) var phase: Phase = .idle

    /// The heard text and what it was taken to mean. Fires on the main actor.
    var onIntent: ((VoiceIntent, String) -> Void)?
    /// Progress the UI can show. Nil clears it.
    var onStatus: ((String?) -> Void)?

    private let settings: VoiceCommandSettings

    private let engine = AVAudioEngine()
    private var recogniseTask: Task<Void, Never>?
    private var timeout: Task<Void, Never>?

    /// The labels on the card being answered, so "the second one" and the
    /// option's own words both work. Empty for an approval card.
    private var options: [String] = []

    init(settings: VoiceCommandSettings) {
        self.settings = settings
    }

    var isRunning: Bool { phase == .preparing || phase == .listening }

    /// Opens the window. Pressing again while listening cancels — the same
    /// escape hatch the camera has, so the key is never a one-way door.
    func begin(options: [String]) {
        Self.logger.notice(
            "begin phase=\(String(describing: self.phase), privacy: .public) enabled=\(self.settings.isEnabled) options=\(options.count)"
        )

        if isRunning {
            stop()
            return
        }
        guard settings.isEnabled else { return }

        self.options = options

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startAfterSpeechAuthorisation()
        case .notDetermined:
            onStatus?(LanguageManager.shared.t("voice.status.requesting"))
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted {
                        self.startAfterSpeechAuthorisation()
                    } else {
                        self.phase = .denied
                        self.onStatus?(LanguageManager.shared.t("voice.status.denied"))
                    }
                }
            }
        case .denied, .restricted:
            phase = .denied
            onStatus?(LanguageManager.shared.t("voice.status.denied"))
        @unknown default:
            phase = .unavailable
        }
    }

    func stop() {
        timeout?.cancel()
        timeout = nil
        recogniseTask?.cancel()
        recogniseTask = nil

        // The tap is what feeds the recogniser; with it gone and the task
        // cancelled, the input stream ends on its own.
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        phase = .idle
        onStatus?(nil)
    }

    // MARK: - Private

    /// True when the microphone can be opened right now without asking anyone.
    ///
    /// Callers that arrive without a keypress use this: a permission dialog
    /// should follow a deliberate action, never a card showing up on its own.
    static var canListenWithoutAsking: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            && SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    /// Recognising speech is a second permission, separate from the microphone.
    /// Without it the audio arrives and nothing is ever transcribed — the window
    /// would close saying nothing was heard, whatever was said into it.
    private func startAfterSpeechAuthorisation() {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            start()
        case .notDetermined:
            onStatus?(LanguageManager.shared.t("voice.status.requesting"))
            // `@Sendable` is load-bearing. Without it Swift 6 infers the
            // closure inherits this method's main-actor isolation, then TCC
            // calls it back on an XPC reply thread and the isolation check
            // traps before the first line runs. The camera's callback next door
            // is already `@Sendable` in its own declaration, which is why that
            // one never had the problem.
            SFSpeechRecognizer.requestAuthorization { @Sendable [weak self] status in
                Task { @MainActor in
                    guard let self else { return }
                    if status == .authorized {
                        self.start()
                    } else {
                        self.phase = .denied
                        self.onStatus?(LanguageManager.shared.t("voice.status.speechDenied"))
                    }
                }
            }
        case .denied, .restricted:
            phase = .denied
            onStatus?(LanguageManager.shared.t("voice.status.speechDenied"))
        @unknown default:
            phase = .unavailable
        }
    }

    private func start() {
        phase = .preparing
        onStatus?(LanguageManager.shared.t("voice.status.preparing"))

        recogniseTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.listen()
            } catch {
                Self.logger.notice("Listening failed: \(String(describing: error), privacy: .public)")
                guard !Task.isCancelled else { return }
                self.stop()
                self.onStatus?(LanguageManager.shared.t("voice.status.unavailable"))
            }
        }

        let seconds = settings.windowSeconds
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.finishByTimeout()
        }
    }

    private func listen() async throws {
        // Speech's streaming analyzer arrived in macOS 26. The app still runs on
        // 14, where this feature simply does not exist rather than crashing.
        guard #available(macOS 26.0, *) else {
            phase = .unavailable
            onStatus?(LanguageManager.shared.t("voice.status.unavailable"))
            return
        }

        let transcriber = SpeechTranscriber(locale: settings.locale, preset: .progressiveTranscription)

        // The model is per-locale and is not on the machine until asked for.
        // Downloading is a visible step rather than a silent one: it is tens of
        // megabytes and it is the user's connection.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            onStatus?(LanguageManager.shared.t("voice.status.downloading"))
            try await request.downloadAndInstall()
        }
        guard !Task.isCancelled else { return }

        // Bounded on purpose. The tap produces a buffer every ~90ms and the
        // recogniser can fall behind; an unbounded stream would then grow for as
        // long as the window lasts. Dropping the oldest audio is the right loss
        // here — the newest words are the answer.
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(
            of: AnalyzerInput.self,
            bufferingPolicy: .bufferingNewest(32)
        )
        defer { continuation.finish() }

        // Constructed with the sequence, so it starts consuming on its own.
        // Calling `start(inputSequence:)` as well would hand it a second source.
        let analyzer = SpeechAnalyzer(inputSequence: stream, modules: [transcriber])
        // Nothing below mentions the analyzer again — it feeds the transcriber
        // from the inside — and ARC is free to release a local at its last use.
        // Released mid-listen, the results stop arriving and the window ends
        // with "nothing heard" no matter what was said. The `defer` is what
        // holds it open until the loop is done.
        defer { withExtendedLifetime(analyzer) {} }

        let format = engine.inputNode.outputFormat(forBus: 0)
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            continuation.yield(AnalyzerInput(buffer: buffer))
        }
        engine.prepare()
        try engine.start()

        phase = .listening
        onStatus?(LanguageManager.shared.t("voice.status.listening"))

        for try await result in transcriber.results {
            guard !Task.isCancelled else { return }
            let heard = String(result.text.characters)
            // Volatile results are the model still changing its mind; acting on
            // one would answer a permission prompt from half a word.
            guard result.isFinal, !heard.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

            let intent = VoiceCommandParser.intent(from: heard, options: options)
            Self.logger.notice(
                "Heard \(heard, privacy: .public) -> \(String(describing: intent), privacy: .public)"
            )
            let deliver = onIntent
            stop()
            deliver?(intent, heard)
            return
        }
    }

    private func finishByTimeout() {
        // Say why the microphone went out. Turning on and off with no
        // explanation is the same silence as never turning on.
        Self.logger.notice("Window closed in phase=\(String(describing: self.phase), privacy: .public)")
        let wasListening = phase == .listening
        stop()
        if wasListening { onStatus?(LanguageManager.shared.t("voice.status.heardNothing")) }
    }
}
