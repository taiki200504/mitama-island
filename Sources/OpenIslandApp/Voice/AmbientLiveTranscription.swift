import AVFoundation
import Foundation
import Speech
import os

/// Only final results enter this accumulator. Short fragments survive a timed
/// flush so a sentence crossing a boundary is not lost.
struct LiveTextBlock {
    var start: Date
    var text = ""

    mutating func append(_ finalText: String) {
        let trimmed = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { text += (text.isEmpty ? "" : "\n") + trimmed }
    }

    mutating func take(end: Date, audio: String?) -> String? {
        guard text.count >= 8 else { return nil }
        let formatter = ISO8601DateFormatter()
        let output = "# start=\(formatter.string(from: start)) end=\(formatter.string(from: end)) audio=\(audio ?? "none")\n\(text)\n"
        text = ""
        start = end
        return output
    }

    static func filename(at date: Date, id: UUID = UUID()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        return "\(formatter.string(from: date))-\(id.uuidString.prefix(8).lowercased()).txt"
    }
}

private actor LiveTextOutput {
    var block: LiveTextBlock
    let audio: String
    init(start: Date, audio: String) {
        block = LiveTextBlock(start: start)
        self.audio = audio
    }
    func append(_ text: String) { block.append(text) }
    func flush() throws {
        let now = Date()
        // Keep the block until the atomic publication succeeds.
        var next = block
        guard let content = next.take(end: now, audio: audio) else { return }
        let directory = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".mitama/earshot/live-in", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(LiveTextBlock.filename(at: now))
        let temporary = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let handle = try FileHandle(forWritingTo: temporary)
        do {
            try handle.write(contentsOf: Data(content.utf8))
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
        block = next
    }
}

/// The tap only copies and enqueues; recognition and disk I/O run elsewhere.
/// Each WAV owns one stream, finished at the same boundary as its recording.
final class AmbientLiveTranscription: @unchecked Sendable {
    private struct Buffer: @unchecked Sendable { let value: AVAudioPCMBuffer }
    private let continuation: AsyncStream<Buffer>.Continuation
    private static let logger = Logger(subsystem: "com.mitama.island", category: "earshot-live")

    init(format: AVAudioFormat, audio: String, start: Date) {
        let (stream, continuation) = AsyncStream<Buffer>.makeStream(bufferingPolicy: .bufferingNewest(64))
        self.continuation = continuation
        Task.detached {
            defer { continuation.finish() }
            guard #available(macOS 26.0, *), SpeechTranscriber.isAvailable,
                  SFSpeechRecognizer.authorizationStatus() == .authorized else {
                Self.logger.notice("live transcription disabled: unavailable or not authorized")
                return
            }
            let transcriber = SpeechTranscriber(locale: Locale(identifier: "ja_JP"), preset: .progressiveTranscription)
            guard await AssetInventory.status(forModules: [transcriber]) == .installed,
                  let target = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: format),
                  let converter = AVAudioConverter(from: format, to: target) else {
                Self.logger.notice("live transcription disabled: Japanese assets or format unavailable")
                return
            }
            let box = AudioConverterBox(converter: converter, outputFormat: target)
            let (inputs, feed) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingNewest(64))
            let analyzer = SpeechAnalyzer(inputSequence: inputs, modules: [transcriber])
            let output = LiveTextOutput(start: start, audio: audio)
            let results = Task {
                for try await result in transcriber.results where result.isFinal {
                    await output.append(String(result.text.characters))
                }
            }
            let timer = Task {
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(45))
                    do { try await output.flush() }
                    catch { Self.logger.notice("live transcription output failed; retaining block for retry") }
                }
            }
            defer { timer.cancel(); withExtendedLifetime(analyzer) {} }
            do {
                for await buffer in stream {
                    if let converted = box.convert(buffer.value) { feed.yield(AnalyzerInput(buffer: converted)) }
                }
                feed.finish()
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                try await results.value
                try await output.flush()
            } catch {
                feed.finish()
                results.cancel()
                await analyzer.cancelAndFinishNow()
                try? await output.flush()
                Self.logger.notice("live transcription disabled: recognition or output failed")
            }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (src, dst) in zip(source, destination) {
            if let from = src.mData, let to = dst.mData { memcpy(to, from, Int(src.mDataByteSize)) }
        }
        continuation.yield(Buffer(value: copy))
    }

    func finish() { continuation.finish() }
}
