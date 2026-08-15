import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Linkstart phrase")
struct LinkstartPhraseTests {
    @Test("The phrase is heard however the recogniser writes it")
    func recognisesTheSpellings() {
        #expect(LinkstartPhrase.isSpoken(in: "リンクスタート"))
        #expect(LinkstartPhrase.isSpoken(in: "リンク スタート"))
        #expect(LinkstartPhrase.isSpoken(in: "リンク・スタート"))
        #expect(LinkstartPhrase.isSpoken(in: "りんくすたーと"))
        #expect(LinkstartPhrase.isSpoken(in: "Link Start"))
        #expect(LinkstartPhrase.isSpoken(in: "link-start"))
        #expect(LinkstartPhrase.isSpoken(in: "LINKSTART"))
    }

    /// What the recogniser actually returned the first time anyone said it out
    /// loud. A Japanese recogniser mixes scripts inside the loanword.
    @Test("Mixed script is heard")
    func recognisesMixedScript() {
        #expect(LinkstartPhrase.isSpoken(in: "Linkスタート"))
        #expect(LinkstartPhrase.isSpoken(in: "リンク start"))
        #expect(LinkstartPhrase.isSpoken(in: "link スタート"))
        #expect(LinkstartPhrase.isSpoken(in: "りんくスタート"))
    }

    /// The halves have to arrive in that order, or "start the link" would do it.
    @Test("The halves must be in order")
    func halvesMustBeInOrder() {
        #expect(!LinkstartPhrase.isSpoken(in: "スタートリンク"))
        #expect(!LinkstartPhrase.isSpoken(in: "start the link"))
    }

    @Test("It is heard inside a longer sentence")
    func recognisesInsideASentence() {
        #expect(LinkstartPhrase.isSpoken(in: "じゃあ、リンクスタート！"))
        #expect(LinkstartPhrase.isSpoken(in: "ok link start now"))
    }

    @Test("Anything else is not the phrase")
    func rejectsEverythingElse() {
        #expect(!LinkstartPhrase.isSpoken(in: ""))
        #expect(!LinkstartPhrase.isSpoken(in: "   "))
        #expect(!LinkstartPhrase.isSpoken(in: "今日はいい天気ですね"))
        #expect(!LinkstartPhrase.isSpoken(in: "start"))
        #expect(!LinkstartPhrase.isSpoken(in: "link"))
        #expect(!LinkstartPhrase.isSpoken(in: "リンク"))
    }

    /// The approval vocabulary lives next door and must not leak into this one:
    /// saying "yes" at the login screen should not be the same as approving
    /// something an agent asked for.
    @Test("Approval words are not the phrase")
    func approvalWordsAreNotThePhrase() {
        #expect(!LinkstartPhrase.isSpoken(in: "はい"))
        #expect(!LinkstartPhrase.isSpoken(in: "yes"))
        #expect(!LinkstartPhrase.isSpoken(in: "allow"))
    }
}
