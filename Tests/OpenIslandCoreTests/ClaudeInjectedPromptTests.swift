import Testing
@testable import OpenIslandCore

struct ClaudeInjectedPromptTests {
    @Test
    func claudeCodesOwnTrafficIsNotAUserPrompt() {
        #expect(ClaudeInjectedPrompt.isInjected("<task-notification> <task-id>a77a502eb</task-id>"))
        #expect(ClaudeInjectedPrompt.isInjected("  <system-reminder>\nfoo</system-reminder>"))
        #expect(ClaudeInjectedPrompt.isInjected("<command-name>/model</command-name>"))
        #expect(ClaudeInjectedPrompt.isInjected("<local-command-stdout>ok</local-command-stdout>"))
    }

    @Test
    func whatTheUserTypedStaysEvenWhenItStartsWithAnAngleBracket() {
        #expect(!ClaudeInjectedPrompt.isInjected("直してください"))
        #expect(!ClaudeInjectedPrompt.isInjected("<div> が崩れている"))
        #expect(!ClaudeInjectedPrompt.isInjected("<task-notificationer> is a word"))
        #expect(ClaudeInjectedPrompt.userText("fix the login") == "fix the login")
        #expect(ClaudeInjectedPrompt.userText("<task-notification>x") == nil)
        #expect(ClaudeInjectedPrompt.userText(nil) == nil)
    }

    @Test
    func anInjectedPromptNeverBecomesTheSessionName() {
        #expect(SessionAutoName.derive(from: "<task-notification> <task-id>abc</task-id>") == nil)
        #expect(SessionAutoName.derive(from: "Fix the login") != nil)
    }
}
