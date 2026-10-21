import Foundation
import Testing
@testable import OpenIslandApp

@Suite struct LiveTextBlockTests {
    @Test func finalBlocksAndHeader() {
        let start = Date(timeIntervalSince1970: 0)
        var block = LiveTextBlock(start: start)
        block.append("  1234567  ")
        #expect(block.take(end: start.addingTimeInterval(45), audio: nil) == nil)
        block.append("8")
        #expect(block.take(end: start.addingTimeInterval(90), audio: "capture.wav") == "# start=1970-01-01T00:00:00Z end=1970-01-01T00:01:30Z audio=capture.wav\n1234567\n8\n")
        #expect(block.text.isEmpty)
        #expect(block.start == start.addingTimeInterval(90))
        #expect(block.take(end: start.addingTimeInterval(135), audio: nil) == nil)
    }
    @Test func blankResultsDoNotCountAsText() {
        let start = Date(timeIntervalSince1970: 0)
        var block = LiveTextBlock(start: start)
        block.append(" \n ")
        block.append(" 1234567 ")
        #expect(block.take(end: start.addingTimeInterval(45), audio: nil) == nil)
        #expect(block.start == start)
    }
    @Test func exactMinimumAndNoAudio() {
        var block = LiveTextBlock(start: Date(timeIntervalSince1970: 0))
        block.append("あいうえおかきく")
        #expect(block.take(end: Date(timeIntervalSince1970: 45), audio: nil)?.hasSuffix("audio=none\nあいうえおかきく\n") == true)
    }
    @Test @MainActor func preferenceDefaultsOnAndPersists() throws {
        let name = "LiveTextBlockTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = PreferenceStore(suite: defaults)
        let settings = AmbientListenSettings(store: store)
        #expect(settings.liveTranscriptionEnabled)
        settings.liveTranscriptionEnabled = false
        #expect(!AmbientListenSettings(store: store).liveTranscriptionEnabled)
    }
    @Test func utcFilename() {
        #expect(LiveTextBlock.filename(at: Date(timeIntervalSince1970: 0), id: UUID(uuidString: "ABCDEF01-2345-6789-ABCD-EF0123456789")!) == "19700101T000000-abcdef01.txt")
    }
}
