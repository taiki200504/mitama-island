import Foundation
import OpenIslandCore

extension AppModel {
    private static let completedSessionCountKey = "island.level.completedSessions"

    /// Every non-interrupted session completion ever seen, kept across launches.
    var completedSessionCount: Int {
        get { UserDefaults.standard.integer(forKey: Self.completedSessionCountKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.completedSessionCountKey) }
    }

    /// Counts one completion and, when it crosses into a new level, remembers
    /// which session did it so that session's banner can announce the level.
    func recordCompletionForLevel(_ event: AgentEvent) {
        guard case let .sessionCompleted(payload) = event, payload.isInterrupt != true else { return }
        let before = completedSessionCount
        completedSessionCount = before + 1
        if let level = IslandLevel.levelReached(from: before, to: before + 1) {
            pendingLevelUp = (sessionID: payload.sessionID, level: level)
        } else {
            pendingLevelUp = nil
        }
    }
}
