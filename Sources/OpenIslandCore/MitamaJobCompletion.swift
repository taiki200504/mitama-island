import Foundation

/// Tracks newly completed jobs for sneak peek notifications.
public struct MitamaJobCompletion: Equatable, Sendable {
    /// The objective of the newly completed job
    public let objective: String
    /// When it completed
    public let completedAt: Date

    public init(objective: String, completedAt: Date) {
        self.objective = objective
        self.completedAt = completedAt
    }
}

/// Detects which jobs are new since the last poll.
public enum MitamaJobCompletionDetector {
    /// Compares current completed jobs against the previous poll state.
    /// Returns only jobs that completed AFTER the previous poll timestamp.
    ///
    /// On the first poll (no previous state), returns empty array even if there
    /// are completed jobs, to avoid bursting the user with old notifications.
    ///
    /// - Parameters:
    ///   - current: Current list of completed jobs (newest first)
    ///   - lastPollTime: The timestamp of the previous poll, or nil if first poll
    /// - Returns: New completions since lastPollTime (oldest first for sneak peek order)
    public static func detectNew(
        current: [MitamaJobCompletion],
        since lastPollTime: Date?
    ) -> [MitamaJobCompletion] {
        guard let lastPollTime else {
            // First poll: don't fire a burst of notifications for historical jobs
            return []
        }

        // Filter to jobs completed after the last poll (current is newest first)
        let new = current.filter { $0.completedAt > lastPollTime }
        // Return oldest first so sneak peeks fire in completion order
        return new.reversed()
    }
}
