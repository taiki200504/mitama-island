import Testing
@testable import OpenIslandCore

@Suite("Session auto-naming")
struct SessionAutoNameTests {
    @Test("A short prompt becomes the name unchanged")
    func shortPrompt() {
        #expect(SessionAutoName.derive(from: "Fix the login redirect") == "Fix the login redirect")
    }

    @Test("Filler openers are dropped")
    func stripsFiller() {
        #expect(SessionAutoName.derive(from: "Please fix the login redirect") == "Fix the login redirect")
        #expect(SessionAutoName.derive(from: "Could you please fix the login") == "Fix the login")
    }

    /// "Can you see …" must keep its subject — the opener is only filler at the
    /// very start, and only when it leaves something behind.
    @Test("A stripped opener never eats the subject")
    func keepsSubject() {
        let name = SessionAutoName.derive(from: "Can you see the fix in canvas.ts")
        #expect(name == "See the fix in canvas.ts")
    }

    @Test("Only the first sentence is used")
    func firstSentenceOnly() {
        let name = SessionAutoName.derive(from: "Fix the login redirect. It 500s on Safari.")
        #expect(name == "Fix the login redirect")
    }

    /// A pasted stack trace's first line is the only part that reads as a
    /// request; the rest would fill the row with noise.
    @Test("Only the first line is used")
    func firstLineOnly() {
        let name = SessionAutoName.derive(from: "Fix this crash\n\nThread 0:\n  0x00 foo")
        #expect(name == "Fix this crash")
    }

    @Test("Leading blank lines are skipped")
    func skipsLeadingBlanks() {
        #expect(SessionAutoName.derive(from: "\n\n  Fix the crash") == "Fix the crash")
    }

    /// A name that ends mid-word reads as a rendering bug rather than a summary.
    @Test("Long prompts are cut at a word boundary")
    func truncatesOnWords() {
        let name = SessionAutoName.derive(
            from: "Rewrite the authentication middleware so it validates refresh tokens"
        )
        let unwrapped = name ?? ""
        #expect(unwrapped.count <= SessionAutoName.maximumLength + 1)
        #expect(unwrapped.hasSuffix("…"))
        #expect(!unwrapped.contains("valida…"))
    }

    /// Japanese has no spaces to break on, so the hard cut is the right answer
    /// there rather than returning the whole paragraph.
    @Test("A language without spaces still gets cut")
    func truncatesWithoutSpaces() {
        let long = String(repeating: "認", count: 80)
        let name = SessionAutoName.derive(from: long) ?? ""
        #expect(name.count == SessionAutoName.maximumLength + 1)
    }

    @Test("Japanese sentence breaks are honoured")
    func japaneseSentenceBreak() {
        #expect(SessionAutoName.derive(from: "ログインの不具合を直して。Safari で500になる。") == "ログインの不具合を直して")
    }

    /// The caller keeps the workspace name in these cases — a blank headline
    /// would be worse than the repeated one this feature exists to fix.
    @Test("Nothing usable returns nothing")
    func emptyInput() {
        #expect(SessionAutoName.derive(from: nil) == nil)
        #expect(SessionAutoName.derive(from: "") == nil)
        #expect(SessionAutoName.derive(from: "   \n  ") == nil)
        #expect(SessionAutoName.derive(from: "...") == nil)
    }

    /// A prompt that is nothing but filler has no subject to show.
    @Test("Pure filler returns nothing")
    func onlyFiller() {
        #expect(SessionAutoName.derive(from: "please") == nil)
    }

    @Test("The same prompt always gives the same name")
    func deterministic() {
        let prompt = "Please rewrite the parser. It is slow."
        #expect(SessionAutoName.derive(from: prompt) == SessionAutoName.derive(from: prompt))
    }
}
