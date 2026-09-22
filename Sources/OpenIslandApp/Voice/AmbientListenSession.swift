import AVFoundation
import AppKit
import Foundation
import Observation
import os

/// Keeps the microphone open and writes what it hears to disk, in files split
/// by silence. Nothing is recognised here and nothing is sent anywhere — the
/// batch under `mitama-os/scripts/earshot/` picks the files up, transcribes
/// them locally, and decides what to do with them.
///
/// This is the opposite bargain from `VoiceCommandSession`, which opens the
/// microphone for eight seconds after a keypress. That file's comment argues a
/// standing microphone is worse than a standing camera, and it is right: the
/// orange indicator burns all day and speech is what gets captured. This exists
/// anyway because it was asked for, so the cost is paid openly:
///
/// - off by default, behind its own switch, separate from voice commands
/// - paused while a call app is running (the other side never agreed to this)
/// - audio is written only under `~/.mitama/earshot/audio/`, where the batch
///   deletes it on a timer — 24 hours normally, one hour when someone else
///   may be in the room
///
/// The voice-activity test is a plain RMS threshold. A model would be better at
/// telling speech from a fan, but the batch already throws away everything the
/// transcriber returns with low confidence, so a cheap gate is enough here.
@MainActor
@Observable
final class AmbientListenSession {
    enum Phase: Equatable, Sendable {
        case idle
        case listening
        /// Running, but holding the microphone shut because a call is up.
        case pausedForCall
        case denied
        case unavailable
    }

    private static let logger = Logger(subsystem: "com.mitama.island", category: "earshot")

    /// Apps that mean someone else is on the line. Browser-based calls are not
    /// detectable this way and are not guessed at.
    private static let callAppBundleIdentifiers: Set<String> = [
        "us.zoom.xos",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.apple.FaceTime",
        "com.cisco.webexmeetingsapp",
        "com.skype.skype",
    ]

    private(set) var phase: Phase = .idle
    /// Seconds of audio written in the current file. The UI can show it so the
    /// person can see the microphone is open without opening Settings.
    private(set) var currentSegmentSeconds: Double = 0

    private let settings: AmbientListenSettings
    private let engine = AVAudioEngine()
    private let writer: SegmentWriter
    private var callWatch: Task<Void, Never>?

    init(settings: AmbientListenSettings, directory: URL? = nil) {
        self.settings = settings
        self.writer = SegmentWriter(directory: directory ?? Self.defaultDirectory)
    }

    static var defaultDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".mitama/earshot/audio", isDirectory: true)
    }

    var isRunning: Bool { phase == .listening || phase == .pausedForCall }

    /// Turns listening on. Does nothing while the switch is off, so the caller
    /// can call this on launch without checking first.
    func start() {
        guard settings.isEnabled else { return }
        guard !isRunning else { return }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginCapture()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { @Sendable [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted { self.beginCapture() } else { self.phase = .denied }
                }
            }
        case .denied, .restricted:
            phase = .denied
        @unknown default:
            phase = .unavailable
        }
    }

    func stop() {
        callWatch?.cancel()
        callWatch = nil
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        writer.close()
        currentSegmentSeconds = 0
        phase = .idle
        Self.logger.notice("stopped")
    }

    /// Called when the switch is flipped in Settings.
    func settingsChanged() {
        if settings.isEnabled {
            start()
        } else {
            stop()
        }
    }

    private func beginCapture() {
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            phase = .unavailable
            Self.logger.error("no usable input format")
            return
        }

        writer.configure(
            format: format,
            silenceToClose: settings.silenceToCloseSeconds,
            maximumSeconds: settings.maximumMinutes * 60
        )

        // The tap runs on the render thread. It must not touch the main actor,
        // so everything it needs lives inside SegmentWriter, which is its own
        // lock-guarded box.
        let writer = self.writer
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            writer.append(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
            phase = .listening
            Self.logger.notice("listening rate=\(format.sampleRate, privacy: .public)")
        } catch {
            input.removeTap(onBus: 0)
            phase = .unavailable
            Self.logger.error("engine failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        startCallWatch()
    }

    /// Polls for call apps. A notification would be tidier, but there is no one
    /// signal that covers every app, and a five-second poll is cheap next to
    /// keeping an audio engine running.
    private func startCallWatch() {
        callWatch?.cancel()
        callWatch = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, self.isRunning else { return }
                self.applyCallState(Self.isCallAppRunning())
                self.currentSegmentSeconds = self.writer.currentSeconds
            }
        }
    }

    private func applyCallState(_ inCall: Bool) {
        guard settings.pauseDuringCalls else { return }
        switch (inCall, phase) {
        case (true, .listening):
            writer.setMuted(true)
            writer.close()
            phase = .pausedForCall
            Self.logger.notice("paused: call app running")
        case (false, .pausedForCall):
            writer.setMuted(false)
            phase = .listening
            Self.logger.notice("resumed: call ended")
        default:
            break
        }
    }

    static func isCallAppRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            guard let identifier = app.bundleIdentifier else { return false }
            return callAppBundleIdentifiers.contains(identifier)
        }
    }
}

/// Writes voiced audio into timestamped WAV files, one per stretch of talking.
///
/// Lives outside the main actor because the audio tap calls it directly. All of
/// its state is behind one lock; the tap is the only writer in practice, but
/// `close()` can arrive from the main actor when listening is switched off.
final class SegmentWriter: @unchecked Sendable {
    /// Below this RMS the buffer counts as silence. Picked to sit above room
    /// tone and fan noise on a laptop microphone while still catching speech
    /// from across a desk.
    private static let voiceThreshold: Float = 0.012

    private let directory: URL
    private let lock = NSLock()

    private var format: AVAudioFormat?
    private var file: AVAudioFile?
    private var silenceToClose: Double = 90
    private var maximumSeconds: Double = 20 * 60
    private var writtenFrames: AVAudioFramePosition = 0
    private var silentFrames: AVAudioFramePosition = 0
    private var muted = false

    init(directory: URL) {
        self.directory = directory
    }

    var currentSeconds: Double {
        lock.lock()
        defer { lock.unlock() }
        guard let format, writtenFrames > 0 else { return 0 }
        return Double(writtenFrames) / format.sampleRate
    }

    func configure(format: AVAudioFormat, silenceToClose: Double, maximumSeconds: Double) {
        lock.lock()
        defer { lock.unlock() }
        self.format = format
        self.silenceToClose = silenceToClose
        self.maximumSeconds = maximumSeconds
    }

    func setMuted(_ muted: Bool) {
        lock.lock()
        defer { lock.unlock() }
        self.muted = muted
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !muted, let format else { return }

        let voiced = Self.rms(of: buffer) >= Self.voiceThreshold
        let frames = AVAudioFramePosition(buffer.frameLength)

        if file == nil {
            // Silence with nothing open is the common case all day. Do nothing
            // until someone actually says something.
            guard voiced else { return }
            guard let opened = Self.openFile(in: directory, format: format) else { return }
            file = opened
            writtenFrames = 0
            silentFrames = 0
        }

        do {
            try file?.write(from: buffer)
        } catch {
            // A failed write means the file is no good. Drop it rather than
            // carry on appending to something half-written.
            closeLocked()
            return
        }
        writtenFrames += frames
        silentFrames = voiced ? 0 : silentFrames + frames

        let silentSeconds = Double(silentFrames) / format.sampleRate
        let totalSeconds = Double(writtenFrames) / format.sampleRate
        if silentSeconds >= silenceToClose || totalSeconds >= maximumSeconds {
            closeLocked()
        }
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        closeLocked()
    }

    private func closeLocked() {
        file = nil
        writtenFrames = 0
        silentFrames = 0
    }

    /// `20260921T204500` — sorts by name and survives being a file name.
    /// Built by hand rather than with a shared formatter: `ISO8601DateFormatter`
    /// is not `Sendable`, and this is called from the audio thread.
    private static func timestamp(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d%02d%02dT%02d%02d%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
            parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0
        )
    }

    private static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let frames = Int(buffer.frameLength)
        var sum: Float = 0
        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = channels[channel]
            for frame in 0..<frames {
                let value = samples[frame]
                sum += value * value
            }
        }
        let count = Float(frames * Int(buffer.format.channelCount))
        return count > 0 ? (sum / count).squareRoot() : 0
    }

    private static func openFile(in directory: URL, format: AVAudioFormat) -> AVAudioFile? {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // The stamp is only good to the second, and a capped file can be
            // followed immediately by the next one. Without the suffix the two
            // land on the same path and the first is overwritten — the second
            // half of a long meeting silently replacing the first.
            let stamp = Self.timestamp(Date())
            let suffix = String(UUID().uuidString.prefix(4)).lowercased()
            let url = directory.appendingPathComponent("\(stamp)-\(suffix)-mac.wav")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
            return try AVAudioFile(forWriting: url, settings: settings)
        } catch {
            return nil
        }
    }
}
