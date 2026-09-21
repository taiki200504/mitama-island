import AVFoundation
import Foundation
import Testing
@testable import OpenIslandApp

/// The part of earshot that decides when a file starts and stops.
///
/// Worth pinning down: it runs all day on the audio thread, and both mistakes
/// are expensive — opening on room tone fills the disk with silence, and never
/// closing turns a day into one unusable file.
@Suite struct AmbientListenSegmentWriterTests {
    private static let sampleRate = 16_000.0

    private static func format() throws -> AVAudioFormat {
        try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
    }

    /// One second of a constant amplitude. 0 is silence; 0.2 is well past the
    /// voice threshold.
    private static func buffer(_ format: AVAudioFormat, amplitude: Float, seconds: Double = 1) throws -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(format.sampleRate * seconds)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let samples = try #require(buffer.floatChannelData)
        for frame in 0..<Int(frames) {
            samples[0][frame] = amplitude
        }
        return buffer
    }

    private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "earshot-\(UUID().uuidString)")
    }

    @Test("Silence alone never opens a file")
    func silenceOpensNothing() throws {
        let directory = Self.temporaryDirectory()
        let writer = SegmentWriter(directory: directory)
        let format = try Self.format()
        writer.configure(format: format, silenceToClose: 5, maximumSeconds: 600)

        for _ in 0..<10 {
            writer.append(try Self.buffer(format, amplitude: 0))
        }

        #expect(writer.currentSeconds == 0)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("A voice opens a file, and the silence after it closes the file")
    func voiceOpensAndSilenceCloses() throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = SegmentWriter(directory: directory)
        let format = try Self.format()
        writer.configure(format: format, silenceToClose: 3, maximumSeconds: 600)

        writer.append(try Self.buffer(format, amplitude: 0.2))
        #expect(writer.currentSeconds > 0)

        // Short silence keeps the file open — a pause mid-sentence is not an end.
        writer.append(try Self.buffer(format, amplitude: 0))
        #expect(writer.currentSeconds > 0)

        // Past the threshold it closes.
        writer.append(try Self.buffer(format, amplitude: 0, seconds: 3))
        #expect(writer.currentSeconds == 0)

        let written = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(written.count == 1)
        #expect(written.allSatisfy { $0.hasSuffix("-mac.wav") })
    }

    @Test("A long stretch of talking is cut at the cap rather than growing forever")
    func longRunIsCappedIntoSeparateFiles() throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = SegmentWriter(directory: directory)
        let format = try Self.format()
        writer.configure(format: format, silenceToClose: 60, maximumSeconds: 2)

        for _ in 0..<3 {
            writer.append(try Self.buffer(format, amplitude: 0.2, seconds: 2))
        }

        let written = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(written.count == 3)
    }

    @Test("Muting stops the writer from opening anything, however loud the room is")
    func mutedWriterStaysShut() throws {
        let directory = Self.temporaryDirectory()
        let writer = SegmentWriter(directory: directory)
        let format = try Self.format()
        writer.configure(format: format, silenceToClose: 5, maximumSeconds: 600)
        writer.setMuted(true)

        writer.append(try Self.buffer(format, amplitude: 0.5))

        #expect(writer.currentSeconds == 0)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}
