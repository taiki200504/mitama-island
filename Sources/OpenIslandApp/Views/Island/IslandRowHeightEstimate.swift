import SwiftUI
import OpenIslandCore

// MARK: - Row Height Estimation

extension AgentSession {
    /// Estimated row height matching `IslandSessionRow` layout for viewport sizing.
    @MainActor func estimatedIslandRowHeight(
        at date: Date,
        fields: IslandSessionCardFields = .all
    ) -> CGFloat {
        let presence = islandPresence(at: date)
        // The shared context always has title + provider/host/mode. Waiting
        // rows permit a second title line and always identify the workspace.
        let scale = max(1, IslandTypography.contentScale)
        var height: CGFloat = 22 + 38 * scale
        if fields.showsProjectName || phase.requiresAttention { height += 20 * scale }
        if phase.requiresAttention { height += 18 * scale }
        guard presence != .inactive else { return height }
        if fields.showsAgentActivity, !phase.requiresAttention, spotlightActivityLineText != nil { height += 20 * scale }
        if fields.showsSubagents,
           let subagents = claudeMetadata?.activeSubagents, !subagents.isEmpty {
            height += 18
            height += CGFloat(subagents.count) * 18  // each subagent row (spacing 4 + text 14)
        }
        if fields.showsTasks,
           let tasks = claudeMetadata?.activeTasks, !tasks.isEmpty {
            height += 17
            height += CGFloat(tasks.count) * 16  // each task row (spacing 3 + text 13)
        }
        return height
    }
}

/// Which optional facts a session row is allowed to carry.
///
/// Defaults to showing everything, so a caller that does not care — a preview, a
/// test, the notification card — keeps the behaviour the row always had.
struct IslandSessionCardFields: Equatable, Sendable {
    var showsTasks: Bool = true
    var showsSubagents: Bool = true
    var showsAgentActivity: Bool = true
    var showsProjectName: Bool = false
    var showsWorktree: Bool = false
    var showsModel: Bool = false

    static let all = IslandSessionCardFields()

    init(
        showsTasks: Bool = true,
        showsSubagents: Bool = true,
        showsAgentActivity: Bool = true,
        showsProjectName: Bool = false,
        showsWorktree: Bool = false,
        showsModel: Bool = false
    ) {
        self.showsTasks = showsTasks
        self.showsSubagents = showsSubagents
        self.showsAgentActivity = showsAgentActivity
        self.showsProjectName = showsProjectName
        self.showsWorktree = showsWorktree
        self.showsModel = showsModel
    }

    @MainActor
    init(display: DisplaySettings) {
        self.init(
            showsTasks: display.showTasks,
            showsSubagents: display.showSubagents,
            showsAgentActivity: display.showAgentActivity,
            showsProjectName: display.showProjectName,
            showsWorktree: display.showWorktree,
            showsModel: display.showModel
        )
    }
}
