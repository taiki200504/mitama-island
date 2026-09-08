import Foundation
import Testing
@testable import OpenIslandCore

@Suite struct MeetingLinkTests {
    @Test(
        "Each recognized provider is found on its own",
        arguments: [
            "https://us02web.zoom.us/j/123456789",
            "https://meet.google.com/abc-defg-hij",
            "https://teams.microsoft.com/l/meetup-join/abc",
            "https://company.webex.com/meet/room",
        ]
    )
    func recognizesEachProvider(url: String) {
        #expect(MeetingLink.find(in: [url])?.absoluteString == url)
    }

    @Test("A link embedded in a paragraph of surrounding text is still found")
    func embeddedInSurroundingText() {
        let notes = """
        Join Zoom Meeting
        https://zoom.us/j/998877665
        Meeting ID: 998 877 665
        """
        #expect(MeetingLink.find(in: [notes])?.absoluteString == "https://zoom.us/j/998877665")
    }

    @Test("An invalid URL is ignored rather than crashing")
    func invalidURLIsIgnored() {
        #expect(MeetingLink.find(in: ["not a url at all"]) == nil)
    }

    @Test("Nil when nothing recognized is present")
    func nilWhenNoneFound() {
        #expect(MeetingLink.find(in: [nil, "会議室Aで対面です", "https://example.com"]) == nil)
    }

    @Test("Nil entries in the list are skipped, not treated as a failure")
    func skipsNilEntries() {
        let url = MeetingLink.find(in: [nil, nil, "https://meet.google.com/xyz-abcd-efg"])
        #expect(url?.host == "meet.google.com")
    }

    @Test("The first match across multiple texts wins")
    func firstMatchWins() {
        let url = MeetingLink.find(in: ["https://meet.google.com/aaa-bbbb-ccc", "https://zoom.us/j/111"])
        #expect(url?.host == "meet.google.com")
    }
}
