import Foundation
import OpenIslandCore

/// Which channels actually wrote audio.
struct MeetingRecordingResult: Equatable, Sendable {
    var micRecorded: Bool
    var systemRecorded: Bool
}

/// Records one meeting into two files: the microphone (this person) and the
/// meeting app's own audio (everyone else). A protocol so the coordinator's
/// start/stop/discard flow can be exercised without TCC permissions.
@MainActor
protocol MeetingRecorder: AnyObject {
    /// Starts both channels. A channel that cannot start (permission refused)
    /// is skipped rather than failing the whole meeting; this throws only when
    /// neither channel could start.
    func start(context: MeetingContext, micURL: URL, systemURL: URL) async throws
    /// Stops and finalises both files.
    func stop() async -> MeetingRecordingResult
}

enum MeetingRecorderError: Error {
    case noChannelStarted
}

#if os(macOS)
import AVFoundation
import CoreMedia
@preconcurrency import ScreenCaptureKit
import os

/// Microphone through `AVAudioEngine`, the meeting app's audio through
/// ScreenCaptureKit's app-audio capture (`capturesAudio` on a filter that
/// includes only the meeting app). Both are written as AAC `.m4a`.
///
/// The standing earshot engine may hold the same microphone at the same time;
/// macOS allows several engines on one input, and earshot pauses its own
/// writing during calls (`AmbientListenSession.pauseDuringCalls`).
@MainActor
final class ScreenCaptureMeetingRecorder: MeetingRecorder {
    private static let logger = Logger(subsystem: "com.mitama.island", category: "meeting")

    private var engine: AVAudioEngine?
    private var micSink: AudioFileSink?
    private var systemCapture: SystemAudioCapture?

    func start(context: MeetingContext, micURL: URL, systemURL: URL) async throws {
        let micStarted = await startMicrophone(url: micURL)
        let capture = SystemAudioCapture(sink: AudioFileSink(url: systemURL))
        let systemStarted = await capture.start(appBundleID: context.appBundleID)
        if systemStarted { systemCapture = capture }
        Self.logger.notice("meeting recorder started mic=\(micStarted) sys=\(systemStarted)")
        guard micStarted || systemStarted else { throw MeetingRecorderError.noChannelStarted }
    }

    func stop() async -> MeetingRecordingResult {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        let systemRecorded = await systemCapture?.stop() ?? false
        let result = MeetingRecordingResult(micRecorded: micSink?.close() ?? false, systemRecorded: systemRecorded)
        micSink = nil
        systemCapture = nil
        return result
    }

    private func startMicrophone(url: URL) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else { return false }
        default:
            return false
        }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return false }
        // The tap runs on the audio thread, so everything it touches lives in
        // the sink, which is its own lock-guarded box (same as earshot).
        let sink = AudioFileSink(url: url)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            sink.write(buffer)
        }
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            Self.logger.notice("mic start failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        self.engine = engine
        self.micSink = sink
        return true
    }
}

/// The meeting app's audio through ScreenCaptureKit. Not on the main actor:
/// ScreenCaptureKit's types are not `Sendable`, so they are created, used and
/// released inside this box and never cross an actor boundary.
final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.mitama.island", category: "meeting")
    let sink: AudioFileSink
    private let queue = DispatchQueue(label: "com.mitama.island.meeting.system-audio")
    private var stream: SCStream?

    init(sink: AudioFileSink) {
        self.sink = sink
    }

    /// `appBundleID == nil` captures every app's audio except the island's.
    func start(appBundleID: String?) async -> Bool {
        // Asking for shareable content is what triggers the Screen Recording
        // prompt; without the grant it throws and the meeting goes mic-only.
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            Self.logger.notice("system audio unavailable: \(error.localizedDescription, privacy: .public)")
            return false
        }
        guard let display = content.displays.first else { return false }

        let filter: SCContentFilter
        if let appBundleID {
            // Helpers carry the parent's ID as a prefix (Chrome's renderer,
            // Teams' WebView) and are where the audio actually plays.
            let apps = content.applications.filter {
                $0.bundleIdentifier == appBundleID || $0.bundleIdentifier.hasPrefix(appBundleID + ".")
            }
            guard !apps.isEmpty else { return false }
            filter = SCContentFilter(display: display, including: apps, exceptingWindows: [])
        } else {
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let own = content.applications.filter { $0.processID == ownPID }
            filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        }

        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        // Video is required by the API but unused: keep it tiny and slow.
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            try await stream.startCapture()
        } catch {
            Self.logger.notice("system audio start failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        self.stream = stream
        return true
    }

    /// Stops the stream and finalises the file. True when it holds audio.
    func stop() async -> Bool {
        if let stream {
            do { try await stream.stopCapture() } catch {
                Self.logger.notice("system audio stop failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        stream = nil
        return sink.close()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, let buffer = Self.pcmBuffer(from: sampleBuffer) else { return }
        sink.write(buffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Self.logger.notice("system audio stream stopped: \(error.localizedDescription, privacy: .public)")
    }

    static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = sampleBuffer.formatDescription,
              var streamDescription = description.audioStreamBasicDescription,
              let format = AVAudioFormat(streamDescription: &streamDescription)
        else { return nil }
        let frames = AVAudioFrameCount(sampleBuffer.numSamples)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList
        )
        return status == noErr ? buffer : nil
    }
}

/// Writes PCM buffers into an AAC `.m4a`, creating the file on the first
/// buffer so its format matches whatever the device delivers. Called from
/// audio threads; all state is behind one lock.
final class AudioFileSink: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var failed = false
    private var framesWritten: AVAudioFramePosition = 0

    init(url: URL) {
        self.url = url
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !failed else { return }
        do {
            if file == nil {
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: buffer.format.sampleRate,
                    AVNumberOfChannelsKey: buffer.format.channelCount,
                    AVEncoderBitRateKey: 64_000 * Int(min(buffer.format.channelCount, 2)),
                ]
                file = try AVAudioFile(
                    forWriting: url,
                    settings: settings,
                    commonFormat: buffer.format.commonFormat,
                    interleaved: buffer.format.isInterleaved
                )
            }
            try file?.write(from: buffer)
            framesWritten += AVAudioFramePosition(buffer.frameLength)
        } catch {
            failed = true
        }
    }

    /// Finalises the file. Returns true when it holds any audio; an empty or
    /// failed file is removed so the manifest never points at nothing.
    func close() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let file {
            if #available(macOS 15.0, *) { file.close() }
        }
        file = nil
        failed = true
        if framesWritten == 0 {
            try? FileManager.default.removeItem(at: url)
            return false
        }
        return FileManager.default.fileExists(atPath: url.path)
    }
}
#endif
