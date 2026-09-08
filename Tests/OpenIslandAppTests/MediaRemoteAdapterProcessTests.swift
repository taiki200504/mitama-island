import Foundation
import Testing
@testable import OpenIslandApp

/// Pins `NDJSONLineSplitter`'s buffering behavior by feeding it raw byte
/// chunks directly — the same "fake pipe" approach
/// `CodexAppServerBufferTests` uses for `CodexAppServerClient`, standing in
/// for a real perl subprocess's `availableData` events without launching
/// one. Nothing here touches `MediaRemoteAdapterProcess.start()`, `perl`, or
/// the vendored framework.
struct MediaRemoteAdapterProcessTests {
    @Test("A single chunk containing one complete line yields that line")
    func oneCompleteLine() {
        var splitter = NDJSONLineSplitter()
        let lines = splitter.feed(Data("{\"type\":\"data\"}\n".utf8))
        #expect(lines == ["{\"type\":\"data\"}"])
    }

    @Test("A line split across two chunks is only reported once both arrive")
    func lineSplitAcrossChunks() {
        var splitter = NDJSONLineSplitter()
        let firstHalf = splitter.feed(Data("{\"payload\":".utf8))
        #expect(firstHalf.isEmpty)

        let secondHalf = splitter.feed(Data("{}}\n".utf8))
        #expect(secondHalf == ["{\"payload\":{}}"])
    }

    @Test("One chunk containing multiple lines yields all of them, in order")
    func multipleLinesInOneChunk() {
        var splitter = NDJSONLineSplitter()
        let lines = splitter.feed(Data("{\"a\":1}\n{\"a\":2}\n{\"a\":3}\n".utf8))
        #expect(lines == ["{\"a\":1}", "{\"a\":2}", "{\"a\":3}"])
    }

    @Test("A trailing partial line stays buffered until it's completed")
    func trailingPartialLineStaysBuffered() {
        var splitter = NDJSONLineSplitter()
        let firstBatch = splitter.feed(Data("{\"a\":1}\n{\"a\":2".utf8))
        #expect(firstBatch == ["{\"a\":1}"])

        let secondBatch = splitter.feed(Data("}\n".utf8))
        #expect(secondBatch == ["{\"a\":2}"])
    }

    @Test("Back-to-back newlines produce no empty lines")
    func emptyLinesAreDropped() {
        var splitter = NDJSONLineSplitter()
        let lines = splitter.feed(Data("\n\n{\"a\":1}\n\n".utf8))
        #expect(lines == ["{\"a\":1}"])
    }

    @Test("Availability is false when the framework can't be resolved")
    func unavailableWithNoFramework() {
        let process = MediaRemoteAdapterProcess(frameworkPath: nil, perlScriptPath: "/usr/bin/true")
        #expect(process.isAvailable == false)
    }

    @Test("Availability is false when the perl script can't be resolved")
    func unavailableWithNoScript() {
        let process = MediaRemoteAdapterProcess(frameworkPath: "/tmp", perlScriptPath: nil)
        #expect(process.isAvailable == false)
    }

    @Test("Starting with nothing resolved reports unavailable rather than throwing")
    func startWithNothingResolvedReportsUnavailable() {
        let process = MediaRemoteAdapterProcess(frameworkPath: nil, perlScriptPath: nil)
        var reportedAvailability: Bool?
        process.onAvailabilityChange = { reportedAvailability = $0 }

        process.start()

        #expect(reportedAvailability == false)
    }
}
