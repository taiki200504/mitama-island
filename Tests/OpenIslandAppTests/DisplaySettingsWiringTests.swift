import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// The display pane ships a mix of live controls and ones waiting on work
/// elsewhere. These tests pin down which is which, so a control cannot quietly
/// slip from one group to the other.
@MainActor
struct DisplaySettingsWiringTests {
    private func makeSettings() -> SettingsStore {
        let name = "display-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return SettingsStore(store: PreferenceStore(suite: suite))
    }

    private func sessionWithDetails() -> AgentSession {
        var session = AgentSession(
            id: "detailed",
            title: "Claude · demo",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Running",
            updatedAt: Date(timeIntervalSince1970: 5_000),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "demo",
                paneTitle: "claude ~/demo",
                workingDirectory: "/tmp/demo",
                terminalSessionID: "ghostty-1"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                transcriptPath: "/tmp/demo.jsonl",
                currentTool: "Edit",
                model: "claude-opus-5",
                worktreeBranch: "feat/settings-display",
                activeSubagents: [
                    ClaudeSubagentInfo(agentID: "a", agentType: "explore"),
                ],
                activeTasks: [
                    ClaudeTaskInfo(id: "t1", title: "map the session state", status: .inProgress),
                    ClaudeTaskInfo(id: "t2", title: "add coverage", status: .completed),
                ]
            )
        )
        session.isProcessAlive = true
        return session
    }

    // MARK: Session card fields

    @Test
    func everySessionCardFieldShowsByDefault() {
        let settings = makeSettings()
        let fields = IslandSessionCardFields(display: settings.display)

        #expect(fields.showsTasks)
        #expect(fields.showsSubagents)
        #expect(fields.showsAgentActivity)
    }

    @Test
    func settingsDriveTheCardFields() {
        let settings = makeSettings()
        settings.display.showTasks = false
        settings.display.showSubagents = false

        let fields = IslandSessionCardFields(display: settings.display)
        #expect(!fields.showsTasks)
        #expect(!fields.showsSubagents)
        #expect(fields.showsAgentActivity)
    }

    /// The row's reserved height has to shrink alongside what it draws, or a
    /// hidden task list leaves a gap where it used to be.
    @Test
    func hidingTasksReducesTheReservedRowHeight() {
        let session = sessionWithDetails()
        let date = Date(timeIntervalSince1970: 5_010)

        let full = session.estimatedIslandRowHeight(at: date, fields: .all)
        let withoutTasks = session.estimatedIslandRowHeight(
            at: date,
            fields: IslandSessionCardFields(showsTasks: false)
        )

        #expect(withoutTasks < full)
    }

    @Test
    func hidingSubagentsReducesTheReservedRowHeight() {
        let session = sessionWithDetails()
        let date = Date(timeIntervalSince1970: 5_010)

        let full = session.estimatedIslandRowHeight(at: date, fields: .all)
        let withoutSubagents = session.estimatedIslandRowHeight(
            at: date,
            fields: IslandSessionCardFields(showsSubagents: false)
        )

        #expect(withoutSubagents < full)
    }

    @Test
    func hidingEverythingOptionalLeavesOnlyTheBaseRow() {
        let session = sessionWithDetails()
        let date = Date(timeIntervalSince1970: 5_010)

        let stripped = session.estimatedIslandRowHeight(
            at: date,
            fields: IslandSessionCardFields(
                showsTasks: false,
                showsSubagents: false,
                showsAgentActivity: false
            )
        )
        let full = session.estimatedIslandRowHeight(at: date, fields: .all)

        #expect(stripped < full)
    }

    // MARK: Panel geometry

    @Test
    func panelSizeDefaultsMatchTheMeasuredSurface() {
        let settings = makeSettings()
        #expect(settings.display.maxPanelHeight == 560)
        #expect(settings.display.maxPanelWidth == 648)
    }

    @Test
    func panelSizeIsAdjustableWithinItsRange() {
        let settings = makeSettings()
        let range = DisplaySettings.Defaults.maxPanelHeightRange

        settings.display.maxPanelHeight = range.lowerBound
        #expect(settings.display.maxPanelHeight == range.lowerBound)

        settings.display.maxPanelHeight = range.upperBound
        #expect(settings.display.maxPanelHeight == range.upperBound)
    }

    // MARK: Honesty of the pending markers

    /// Three of the four metadata switches turned out to have data behind them
    /// after all, so only reasoning effort stays disabled. If a value for it
    /// ever lands, this test is the reminder to make its switch live too.
    @Test
    func onlyReasoningEffortLacksTheDataToRenderIt() {
        let session = sessionWithDetails()

        // These three have a value to show, so their switches are live.
        #expect(session.spotlightProjectBadge == "demo")
        #expect(session.claudeMetadata?.worktreeBranch == "feat/settings-display")
        #expect(session.claudeMetadata?.model == "claude-opus-5")

        #expect(!PendingCapability.reasoningEffortMetadata.isImplemented)
        #expect(!PendingCapability.contentTypographyScale.isImplemented)
        #expect(!PendingCapability.completionCardSizing.isImplemented)
        #expect(!PendingCapability.notchCalibration.isImplemented)
    }

    /// Badge defaults follow the reference product rather than the row's
    /// previous contents — matching it is the point of this work.
    @Test
    func badgeDefaultsFollowTheReferenceProduct() {
        let settings = makeSettings()
        let fields = IslandSessionCardFields(display: settings.display)

        #expect(fields.showsProjectName)
        #expect(fields.showsWorktree)
        #expect(!fields.showsModel)
    }
}
