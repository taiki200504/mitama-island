import Foundation
import OpenIslandCore

extension AppModel {
    /// The row's "view conversation" action, or nil when this session has no
    /// transcript in a format the log can read. Only Claude Code's JSONL for
    /// now — guessing at another agent's format would show the wrong things.
    func conversationLogOpener(for session: AgentSession) -> (() -> Void)? {
        guard let path = session.claudeMetadata?.transcriptPath, !path.isEmpty else { return nil }
        let sessionID = session.id
        return { [weak self] in
            self?.notchOpen(reason: .click, surface: .conversation(sessionID: sessionID))
        }
    }

    /// Whether the log should hide what was said: the same quiet scenes that
    /// hold back notifications, screen sharing among them.
    var conversationLogHidesText: Bool {
        quietScenes.shouldStayQuiet(under: settings.behaviour)
    }
}
