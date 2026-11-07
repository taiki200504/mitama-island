import AppKit
import AVFoundation
import Foundation
import Observation
import OpenIslandCore
import os
import Speech

/// Hold to talk, to ask mitama for something. Recognition is on this Mac only (`requiresOnDeviceRecognition`): no audio
/// leaves the machine and nothing is recorded to a file. It listens only while the button is held, and the
/// microphone never stays on by accident — a quick tap, the 60-second ceiling and the app losing focus each stop it.
@MainActor
@Observable
final class VoiceRequestSession {
    private static let logger = Logger(subsystem: "com.mitama.island", category: "voice-request")

    private(set) var hold = VoiceHold()
    private(set) var statusKey: String?

    /// Delivered once per utterance, when the recognizer's final arrives: (utterance id, text).
    @ObservationIgnored var onHeard: ((String, String) -> Void)?

    private let settings: VoiceRequestSettings
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var limit: Task<Void, Never>?
    @ObservationIgnored private var heldSince = Date()
    @ObservationIgnored private var resignObserver: NSObjectProtocol?

    init(settings: VoiceRequestSettings = VoiceRequestSettings()) {
        self.settings = settings
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.cancelAll() }
        }
    }

    var isListening: Bool { hold.phase == .listening }
    var transcript: String { hold.partialText }

    /// Synchronous on purpose: the press is recorded before anything awaits, so a release that comes right after
    /// (a quick tap) always finds it and the microphone is never opened for a press that is already over.
    func press() {
        guard settings.isEnabled else { statusKey = "settings.mitama.voice.status.off"; return }
        guard let id = hold.press() else { return }
        statusKey = "settings.mitama.voice.status.listening"
        heldSince = Date()
        limit?.cancel()
        limit = Task { [weak self] in
            try? await Task.sleep(for: .seconds(VoiceHold.maxHold))
            guard !Task.isCancelled, let self, self.hold.utteranceID == id,
                  self.hold.shouldAutoRelease(heldFor: Date().timeIntervalSince(self.heldSince)) else { return }
            self.statusKey = "settings.mitama.voice.status.tooLongHeld"
            self.release()
        }
        Task { await start(id) }
    }

    /// The button was let go.
    func release() {
        hold.release()
        endAudio()
    }

    /// The app lost focus (or the pane went away): stop at once and drop the utterance.
    func cancelAll() {
        if hold.appBackgrounded() { teardown(); statusKey = nil }
    }

    // MARK: - Private

    private func start(_ id: String) async {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP")), recognizer.supportsOnDeviceRecognition else {
            fail("settings.mitama.voice.status.unsupported"); return
        }
        guard await authorized() else { fail("settings.mitama.voice.status.denied"); return }
        // Let go while the permission prompts were up (or a quick tap): do not open the microphone at all.
        guard hold.startIfStillHeld(id) else { teardown(); statusKey = nil; return }
        guard recognizer.isAvailable else { fail("settings.mitama.voice.status.unsupported"); return }

        let buffer = SFSpeechAudioBufferRecognitionRequest()
        buffer.requiresOnDeviceRecognition = true
        buffer.shouldReportPartialResults = true
        request = buffer
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { fail("settings.mitama.voice.status.unsupported"); return }
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable audio, _ in buffer.append(audio) }
        task = recognizer.recognitionTask(with: buffer) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor [weak self] in
                guard let self, self.hold.utteranceID == id else { return }
                if let text, !final { self.hold.partial(text) }
                if final || failed { self.finish(text: text ?? self.hold.partialText) }
            }
        }
        do {
            engine.prepare()
            try engine.start()
            // Let go while the engine was starting: stop at once.
            if hold.phase == .awaitingFinal { endAudio() }
        } catch {
            Self.logger.notice("Voice request could not start: \(String(describing: error), privacy: .public)")
            fail("settings.mitama.voice.status.unsupported")
        }
    }

    private func authorized() async -> Bool {
        let microphone: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: microphone = true
        case .notDetermined: microphone = await AVCaptureDevice.requestAccess(for: .audio)
        default: microphone = false
        }
        guard microphone else { return false }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { @Sendable status in continuation.resume(returning: status == .authorized) }
            }
        default: return false
        }
    }

    private func endAudio() {
        if engine.isRunning { engine.inputNode.removeTap(onBus: 0); engine.stop() }
        request?.endAudio()
    }

    private func finish(text: String) {
        let heard = hold.final(text)
        teardown()
        statusKey = heard == nil ? "settings.mitama.voice.status.heardNothing" : nil
        if let heard { onHeard?(heard.utteranceID, heard.text) }
    }

    private func fail(_ key: String) {
        hold.cancel()
        teardown()
        statusKey = key
    }

    private func teardown() {
        limit?.cancel(); limit = nil
        if engine.isRunning { engine.inputNode.removeTap(onBus: 0); engine.stop() }
        task?.cancel()
        task = nil; request = nil
    }
}
