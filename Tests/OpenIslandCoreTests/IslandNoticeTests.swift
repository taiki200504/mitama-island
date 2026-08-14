import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Island notice")
struct IslandNoticeTests {
    private let moment = Date(timeIntervalSince1970: 1_000)

    @Test("A message becomes the notice on screen")
    func acceptsAMessage() {
        let notice = IslandNoticeQueue.accept("マイクのアクセスが拒否されています", over: nil, at: moment)
        #expect(notice?.text == "マイクのアクセスが拒否されています")
        #expect(notice?.shownAt == moment)
    }

    /// The sessions clear their status by sending an empty string. That is not
    /// something to put on screen.
    @Test("Blank text never becomes a notice")
    func ignoresBlankText() {
        #expect(IslandNoticeQueue.accept("", over: nil, at: moment) == nil)
        #expect(IslandNoticeQueue.accept("   \n ", over: nil, at: moment) == nil)
    }

    @Test("Blank text leaves an existing notice alone")
    func blankTextDoesNotClearAnExistingNotice() {
        let existing = IslandNotice(text: "聞いています", shownAt: moment)
        let after = IslandNoticeQueue.accept("", over: existing, at: moment.addingTimeInterval(1))
        #expect(after == existing)
    }

    /// By the time the second explanation arrives, the first is describing a
    /// moment that has passed.
    @Test("A newer message replaces the one on screen")
    func newerMessageWins() {
        let first = IslandNoticeQueue.accept("聞いています", over: nil, at: moment)
        let second = IslandNoticeQueue.accept(
            "「今日はいい天気」と聞こえましたが、意味が取れません",
            over: first,
            at: moment.addingTimeInterval(2)
        )
        #expect(second?.text.hasPrefix("「今日はいい天気」") == true)
        #expect(second?.id != first?.id)
        #expect(second?.shownAt == moment.addingTimeInterval(2))
    }

    @Test("Surrounding whitespace is trimmed")
    func trimsWhitespace() {
        let notice = IslandNoticeQueue.accept("  何も聞き取れませんでした。  ", over: nil, at: moment)
        #expect(notice?.text == "何も聞き取れませんでした。")
    }

    @Test("A notice goes away on its own")
    func expiresOnItsOwn() {
        let notice = IslandNotice(text: "聞いています", shownAt: moment)
        #expect(IslandNoticeQueue.settle(notice, at: moment.addingTimeInterval(1)) == notice)
        #expect(IslandNoticeQueue.settle(notice, at: moment.addingTimeInterval(IslandNotice.lifetime)) == nil)
        #expect(IslandNoticeQueue.settle(notice, at: moment.addingTimeInterval(60)) == nil)
    }

    @Test("Replacing a notice restarts its time on screen")
    func replacementRestartsTheClock() {
        let first = IslandNotice(text: "準備しています", shownAt: moment)
        let almostGone = moment.addingTimeInterval(IslandNotice.lifetime - 0.1)
        let second = IslandNoticeQueue.accept("聞いています", over: first, at: almostGone)

        #expect(IslandNoticeQueue.settle(second, at: almostGone.addingTimeInterval(1)) != nil)
        #expect(second?.remainingTime(at: almostGone) == IslandNotice.lifetime)
    }

    @Test("Nothing on screen stays nothing")
    func settlingNilIsNil() {
        #expect(IslandNoticeQueue.settle(nil, at: moment) == nil)
    }
}
