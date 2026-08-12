import Testing
@testable import OpenIslandCore

@Suite("Voice command parsing")
struct VoiceCommandTests {
    @Test("Japanese approvals and denials remain distinct")
    func japaneseApprovalsAndDenials() {
        #expect(VoiceCommandParser.intent(from: "はい") == .approve)
        #expect(VoiceCommandParser.intent(from: "いいえ") == .deny)
        #expect(VoiceCommandParser.intent(from: "いいよ") == .approve)
    }

    @Test("English approvals and denials are recognised")
    func englishApprovalsAndDenials() {
        #expect(VoiceCommandParser.intent(from: "yes") == .approve)
        #expect(VoiceCommandParser.intent(from: "ok") == .approve)
        #expect(VoiceCommandParser.intent(from: "no") == .deny)
        #expect(VoiceCommandParser.intent(from: "cancel") == .deny)
    }

    @Test("Spoken option numbers use zero-based indices")
    func optionNumbers() {
        let options = ["実装する", "調べる"]
        #expect(VoiceCommandParser.intent(from: "2番", options: options) == .chooseOption(index: 1))
        #expect(VoiceCommandParser.intent(from: "一番", options: options) == .chooseOption(index: 0))
    }

    @Test("Option numbers require options and must be in range")
    func invalidOptionNumbers() {
        #expect(VoiceCommandParser.intent(from: "2番") == .unrecognised)
        #expect(VoiceCommandParser.intent(from: "5番", options: ["実装する", "調べる"]) == .unrecognised)
    }

    @Test("An exact option label chooses that option")
    func exactOptionLabel() {
        #expect(VoiceCommandParser.intent(from: "調べる", options: ["実装する", "調べる"]) == .chooseOption(index: 1))
    }

    @Test("A partial label shared by multiple options is rejected")
    func ambiguousPartialOptionLabel() {
        let options = ["あとで確認", "あとで実行"]
        #expect(VoiceCommandParser.intent(from: "あとで", options: options) == .unrecognised)
    }

    @Test("Ambiguous, unrelated, and blank speech is rejected")
    func unrecognisedSpeech() {
        #expect(VoiceCommandParser.intent(from: "えーっと、たぶん") == .unrecognised)
        #expect(VoiceCommandParser.intent(from: "はい、じゃなくていいえ") == .unrecognised)
        #expect(VoiceCommandParser.intent(from: "") == .unrecognised)
        #expect(VoiceCommandParser.intent(from: "   ") == .unrecognised)
    }
}
