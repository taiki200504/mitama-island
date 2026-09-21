import Foundation
import OpenIslandCore

enum IslandSurface: Equatable {
    case sessionList(actionableSessionID: String? = nil)
    /// Placeholder surfaces for closed-island accessories that don't have
    /// their own opened content yet — a later PR fills each of these in.
    case nowPlaying
    case clipboard
    case timer
    /// Where you left off, and the one next step you wrote down for yourself.
    case focusCard
    /// One session's conversation, read from its transcript.
    case conversation(sessionID: String)

    var sessionID: String? {
        switch self {
        case let .sessionList(actionableSessionID):
            actionableSessionID
        // Not `actionableSessionID`: the log is something you asked to read,
        // not a notification card that dismisses itself.
        case .nowPlaying, .clipboard, .timer, .focusCard, .conversation:
            nil
        }
    }

    var isNotificationCard: Bool {
        sessionID != nil
    }

    func autoDismissesWhenPresentedAsNotification(session: AgentSession?) -> Bool {
        guard sessionID != nil else { return false }
        return session?.phase == .completed
    }

    static func notificationSurface(for event: AgentEvent) -> IslandSurface? {
        switch event {
        case let .permissionRequested(payload):
            .sessionList(actionableSessionID: payload.sessionID)
        case let .questionAsked(payload):
            .sessionList(actionableSessionID: payload.sessionID)
        case let .sessionCompleted(payload):
            payload.isInterrupt == true ? nil : .sessionList(actionableSessionID: payload.sessionID)
        default:
            nil
        }
    }

    func matchesCurrentState(of session: AgentSession?) -> Bool {
        guard sessionID != nil else {
            return true
        }

        guard let session else {
            return false
        }

        switch session.phase {
        case .waitingForApproval:
            return session.permissionRequest != nil
        case .waitingForAnswer:
            return session.questionPrompt != nil
        case .completed:
            return true
        case .running:
            return false
        }
    }
}
