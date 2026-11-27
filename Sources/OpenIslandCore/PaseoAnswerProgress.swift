import Foundation

public enum PaseoAnswerChannel: Equatable, Sendable {
    case paseoSDK
    case claudeHook
    case remoteRelay
}

/// In-flight answer the island is waiting to see progress for.
public struct PaseoAnswerFollowthrough: Equatable, Sendable {
    public static let confirmationTimeout: TimeInterval = 25

    public var displaySessionID: String
    public var targetSessionID: String
    public var answeredRequestID: String?
    public var answeredPromptID: UUID?
    /// When set, completion should mirror allow/deny semantics after resume is confirmed.
    public var permissionApproved: Bool?
    public var channel: PaseoAnswerChannel
    public var submittedAt: Date
    public var deadline: Date
    public var baselineSessionUpdatedAt: Date

    public init(
        displaySessionID: String,
        targetSessionID: String,
        answeredRequestID: String? = nil,
        answeredPromptID: UUID? = nil,
        permissionApproved: Bool? = nil,
        channel: PaseoAnswerChannel,
        submittedAt: Date = .now,
        baselineSessionUpdatedAt: Date
    ) {
        self.displaySessionID = displaySessionID
        self.targetSessionID = targetSessionID
        self.answeredRequestID = answeredRequestID
        self.answeredPromptID = answeredPromptID
        self.permissionApproved = permissionApproved
        self.channel = channel
        self.submittedAt = submittedAt
        self.deadline = submittedAt.addingTimeInterval(Self.confirmationTimeout)
        self.baselineSessionUpdatedAt = baselineSessionUpdatedAt
    }
}

public enum PaseoResumeEvidence: Equatable, Sendable {
    case sessionActivity
    case sessionCompleted
    case subsequentRequest
}

public enum PaseoAnswerProgress {
    /// Progress must come from real agent events on the target native session.
    /// Pending disappearance, snapshot timestamps, and attention flags are excluded.
    public static func evidence(from event: AgentEvent, submission: PaseoAnswerFollowthrough) -> PaseoResumeEvidence? {
        let after = submission.submittedAt
        switch event {
        case let .activityUpdated(payload):
            guard payload.sessionID == submission.targetSessionID, payload.timestamp > after else { return nil }
            guard payload.phase == .running || payload.phase == .completed else { return nil }
            guard payload.timestamp > submission.baselineSessionUpdatedAt else { return nil }
            return .sessionActivity
        case let .sessionCompleted(payload):
            guard payload.sessionID == submission.targetSessionID, payload.timestamp > after else { return nil }
            return .sessionCompleted
        case let .permissionRequested(payload):
            guard payload.sessionID == submission.targetSessionID, payload.timestamp > after else { return nil }
            if let answered = submission.answeredRequestID,
               payload.request.paseoContext?.requestID == answered { return nil }
            if let prompt = submission.answeredPromptID, payload.request.id == prompt { return nil }
            return .subsequentRequest
        case let .questionAsked(payload):
            guard payload.sessionID == submission.targetSessionID, payload.timestamp > after else { return nil }
            if payload.prompt.id == submission.answeredPromptID { return nil }
            return .subsequentRequest
        default:
            return nil
        }
    }
}