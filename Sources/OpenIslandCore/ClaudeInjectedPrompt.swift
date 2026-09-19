import Foundation

/// Claude Code writes some of its own traffic into the conversation as if the
/// user had typed it: background-task results (`<task-notification>`), slash
/// command echoes (`<command-name>`), local command output, reminders. They
/// are not something the user said, so they must never become the session's
/// "last prompt" or its title — the island was showing `<task-notification>`
/// as a session name and 「あなた： <task-notification> <task-id>…」 as the
/// latest message.
public enum ClaudeInjectedPrompt {
    static let tags: [String] = [
        "task-notification",
        "system-reminder",
        "command-name",
        "command-message",
        "command-args",
        "local-command-caveat",
        "local-command-stdout",
        "local-command-stderr",
        "bash-input",
        "bash-stdout",
        "bash-stderr",
        "user-prompt-submit-hook",
    ]

    /// Whether `text` is one of those injected messages rather than
    /// something the user wrote.
    public static func isInjected(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<") else { return false }
        return tags.contains { trimmed.hasPrefix("<\($0)>") || trimmed.hasPrefix("<\($0) ") }
    }

    /// `text` unless it is injected — for the places that take "the user's
    /// prompt" and would otherwise store the injected message as one.
    public static func userText(_ text: String?) -> String? {
        guard let text, !isInjected(text) else { return nil }
        return text
    }
}
