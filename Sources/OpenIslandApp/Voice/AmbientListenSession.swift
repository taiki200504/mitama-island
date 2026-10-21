import AVFoundation
import AppKit
import Foundation
import Observation
import os

/// Keeps the microphone open and writes what it hears to disk, in files split
/// by silence. Recognition is on-device and nothing is sent anywhere — the
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
        case stalled
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
    private var engine = AVAudioEngine()
    /// Engines replaced by `restartCapture`, held until CoreAudio has finished
    /// delivering device-change callbacks to them. Releasing one immediately
    /// let a late HAL property notification land in its freed IO unit
    /// (SIGSEGV in AVAudioIOUnit::IOUnitPropertyListener, 2026-10-20 15:17).
    private var retiredEngines: [AVAudioEngine] = []
    private var configurationObserver: NSObjectProtocol?
    private var engineGeneration = UUID()
    private var tapInstalled = false
    private var lastRestartAt: Date?
    private var recoveryAttempted = false
    private var captureStartedAt = Date()
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

    var isRunning: Bool { phase == .listening || phase == .pausedForCall || phase == .stalled }

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
        tearDownEngine()
        lastRestartAt = nil
        recoveryAttempted = false
        writer.setMuted(false)
        writer.close()
        currentSegmentSeconds = 0
        phase = .idle
        Self.logger.notice("stopped")
    }

    /// Called when the switch is flipped in Settings.
    func settingsChanged() {
        if settings.isEnabled {
            writer.setLiveTranscriptionEnabled(settings.liveTranscriptionEnabled)
            start()
        } else {
            stop()
        }
    }

    private func tearDownEngine() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        engineGeneration = UUID()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        writer.close()
    }

    private func restartCapture(now: Date) {
        guard lastRestartAt.map({ now.timeIntervalSince($0) >= 5 }) ?? true else { return }
        lastRestartAt = now
        let wasPaused = phase == .pausedForCall
        tearDownEngine()
        let retired = engine
        retiredEngines.append(retired)
        engine = AVAudioEngine()
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.retiredEngines.removeAll { $0 === retired }
        }
        beginCapture()
        if phase == .unavailable { phase = .stalled }
        if wasPaused, phase == .listening { phase = .pausedForCall }
    }

    private func beginCapture() {
        captureStartedAt = .now
        // No `BuiltInMicrophone.pin` here. With the pin the engine starts and
        // the orange indicator lights, but the tap never receives a buffer —
        // nothing reached disk from 10-15 (#115) to 10-20. The standing mic
        // follows the system input instead.
        let input = engine.inputNode
        // The output side, not the input side: after `pin` the input side can
        // still report the previous default device (a 16 kHz Bluetooth
        // headset), and a tap in that format makes `start()` fail with -10868.
        // Measured 2026-10-19 with OpenComm2 as the default input.
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            phase = .unavailable
            Self.logger.error("no usable input format")
            return
        }

        writer.configure(
            format: format,
            silenceToClose: settings.silenceToCloseSeconds,
            maximumSeconds: settings.maximumMinutes * 60,
            liveTranscription: settings.liveTranscriptionEnabled
        )

        // The tap runs on the render thread. It must not touch the main actor,
        // so everything it needs lives inside SegmentWriter, which is its own
        // lock-guarded box.
        let writer = self.writer
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            writer.append(buffer)
        }

        tapInstalled = true
        let generation = engineGeneration
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning, self.engineGeneration == generation else { return }
                self.restartCapture(now: .now)
            }
        }

        do {
            engine.prepare()
            try engine.start()
            phase = .listening
            Self.logger.notice("listening rate=\(format.sampleRate, privacy: .public)")
        } catch {
            tearDownEngine()
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
        guard callWatch == nil else { return }
        callWatch = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                guard let self, self.isRunning else { return }
                self.applyCallState(Self.isCallAppRunning())
                self.checkInputHealth(now: .now)
                self.currentSegmentSeconds = self.writer.currentSeconds
            }
        }
    }

    nonisolated static func isInputStalled(now: Date, lastBufferAt: Date, threshold: TimeInterval = 10) -> Bool {
        now.timeIntervalSince(lastBufferAt) >= threshold
    }

    private func checkInputHealth(now: Date) {
        guard phase == .listening || phase == .stalled else { return }
        if !Self.isInputStalled(now: now, lastBufferAt: max(writer.lastBufferAt, captureStartedAt)) {
            if writer.lastBufferAt >= captureStartedAt {
                recoveryAttempted = false
                phase = .listening
            }
        } else if !recoveryAttempted {
            guard lastRestartAt.map({ now.timeIntervalSince($0) >= 5 }) ?? true else { return }
            recoveryAttempted = true
            restartCapture(now: now)
        } else {
            phase = .stalled
        }
    }

    private func applyCallState(_ inCall: Bool) {
        guard settings.pauseDuringCalls else { return }
        switch (inCall, phase) {
        case (true, .listening), (true, .stalled):
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
    // 0.012 was tuned on the built-in mic. A Bluetooth headset (OpenComm2,
    // 16 kHz) peaks around 0.008 on speech, so nothing was ever kept.
    private static let voiceThreshold: Float = 0.004

    private let directory: URL
    private let lock = NSLock()

    private var format: AVAudioFormat?
    private var file: AVAudioFile?
    private var silenceToClose: Double = 90
    private var maximumSeconds: Double = 20 * 60
    private var writtenFrames: AVAudioFramePosition = 0
    private var silentFrames: AVAudioFramePosition = 0
    private var liveTranscriptionEnabled = false
    private var liveTranscription: AmbientLiveTranscription?
    private var muted = false
    private var lastReceivedAt = Date.distantPast

    var lastBufferAt: Date {
        lock.lock()
        defer { lock.unlock() }
        return lastReceivedAt
    }

    init(directory: URL) {
        self.directory = directory
    }

    var currentSeconds: Double {
        lock.lock()
        defer { lock.unlock() }
        guard let format, writtenFrames > 0 else { return 0 }
        return Double(writtenFrames) / format.sampleRate
    }

    func configure(format: AVAudioFormat, silenceToClose: Double, maximumSeconds: Double, liveTranscription: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        self.liveTranscriptionEnabled = liveTranscription
        self.format = format
        self.silenceToClose = silenceToClose
        self.maximumSeconds = maximumSeconds
    }

    private var peakLevel: Float = 0
    private var levelFrames: AVAudioFramePosition = 0
    private static let levelLogger = Logger(subsystem: "com.mitama.island", category: "earshot")

    func setLiveTranscriptionEnabled(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        liveTranscriptionEnabled = enabled
        if !enabled {
            liveTranscription?.finish()
            liveTranscription = nil
        }
    }

    func setMuted(_ muted: Bool) {
        lock.lock()
        defer { lock.unlock() }
        self.muted = muted
        if muted { closeLocked() }
    }

    func append(_ buffer: AVAudioPCMBuffer, now: Date = .now) {
        lock.lock()
        defer { lock.unlock() }
        lastReceivedAt = now
        guard !muted, let format else { return }

        let level = Self.rms(of: buffer)
        let voiced = level >= Self.voiceThreshold
        let frames = AVAudioFramePosition(buffer.frameLength)

        // One line a minute with the loudest buffer, so "is it hearing me"
        // has an answer without opening a debugger.
        peakLevel = max(peakLevel, level)
        levelFrames += frames
        if Double(levelFrames) >= format.sampleRate * 60 {
            Self.levelLogger.notice("level peak=\(self.peakLevel, privacy: .public) threshold=\(Self.voiceThreshold, privacy: .public) open=\(self.file != nil, privacy: .public)")
            peakLevel = 0
            levelFrames = 0
        }

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
        if liveTranscriptionEnabled, liveTranscription == nil, let file {
            liveTranscription = AmbientLiveTranscription(format: format, audio: file.url.lastPathComponent, start: now)
        }
        liveTranscription?.append(buffer)
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
        liveTranscription?.finish()
        liveTranscription = nil
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
