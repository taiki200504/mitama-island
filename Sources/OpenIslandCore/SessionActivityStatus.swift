import Foundation

/// Analyzes whether a running session has stalled (stopped responding).
///
/// A session is considered stalled when:
/// - It is in `.running` phase
/// - No activity (hook event, updatedAt from reducer) for ≥ 300 seconds (5 minutes)
///
/// Activity timestamp comes from SessionState.updatedAt (managed by reducer),
/// not from file monitoring.
///
/// This pure function has no I/O side effects.
public struct SessionActivityStatus: Sendable {
    /// Duration threshold: session is stalled if inert for this long (5 minutes).
    /// Threshold is conservative to avoid false positives from API delays or JSONL flushes.
    public static let stallThreshold: TimeInterval = 300

    /// Determines if a session is stalled based on current state and last activity time.
    ///
    /// - Parameters:
    ///   - phase: Session's current phase
    ///   - lastActivityTime: Timestamp of last transcript update or hook event
    ///   - now: Reference time (defaults to current time)
    ///
    /// - Returns: `true` if session is running but no activity for ≥ 120 seconds
    public static func isStalled(phase: SessionPhase, lastActivityTime: Date?, now: Date = .now) -> Bool {
        guard phase == .running else { return false }
        guard let lastActivityTime else { return false }

        let elapsedSeconds = now.timeIntervalSince(lastActivityTime)
        return elapsedSeconds >= stallThreshold
    }

    /// Human-readable elapsed time since last activity (e.g., "3m", "45s").
    public static func elapsedTimeText(since lastActivityTime: Date, now: Date = .now) -> String {
        let elapsedSeconds = now.timeIntervalSince(lastActivityTime)

        if elapsedSeconds < 60 {
            return String(format: "%.0fs", elapsedSeconds)
        }

        let elapsedMinutes = Int(elapsedSeconds / 60)
        if elapsedMinutes < 60 {
            return "\(elapsedMinutes)m"
        }

        let elapsedHours = elapsedMinutes / 60
        return "\(elapsedHours)h"
    }
}
