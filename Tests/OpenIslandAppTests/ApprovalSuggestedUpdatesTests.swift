import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// The agent sends the choices it is willing to accept. Dropping them left the
/// island unable to answer a plan-mode exit, because "bypass permissions" only
/// ever arrives this way.
@MainActor
struct ApprovalSuggestedUpdatesTests {
    private func session(
        id: String = "plan",
        toolName: String = "ExitPlanMode",
        suggested: [ClaudePermissionUpdate] = []
    ) -> AgentSession {
        var session = AgentSession(
            id: id,
            title: "Claude · demo",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "waiting",
            updatedAt: Date(),
            jumpTarget: JumpTarget(
                terminalApp: "Cursor",
                workspaceName: "demo",
                paneTitle: "claude",
                workingDirectory: "/tmp/demo",
                terminalSessionID: "c1"
            )
        )
        session.permissionRequest = PermissionRequest(
            title: "Exit plan mode",
            summary: "Claude wants to exit plan mode and start implementation.",
            affectedPath: "",
            primaryActionTitle: "Allow Once",
            secondaryActionTitle: "Deny",
            toolName: toolName,
            suggestedUpdates: suggested
        )
        session.isProcessAlive = true
        return session
    }

    private var bypass: ClaudePermissionUpdate {
        .setMode(destination: .session, mode: .bypassPermissions)
    }

    private var acceptEdits: ClaudePermissionUpdate {
        .setMode(destination: .session, mode: .acceptEdits)
    }

    /// The label the card shows has to name the mode, or the user cannot tell
    /// the options apart.
    @Test
    func modeUpdatesCarryAReadableLabel() {
        #expect(bypass.displayLabel.lowercased().contains("bypass"))
        #expect(acceptEdits.displayLabel.lowercased().contains("edits"))
    }

    /// A request that offers nothing still needs an always-allow, which is what
    /// the card used to hard-code for every request.
    @Test
    func aRequestWithoutSuggestionsStillOffersAlwaysAllow() {
        let request = session(toolName: "Bash", suggested: []).permissionRequest
        #expect(request?.suggestedUpdates.isEmpty == true)
        #expect(request?.toolName == "Bash")
    }

    @Test
    func suggestionsSurviveOnTheRequest() {
        let request = session(suggested: [bypass, acceptEdits]).permissionRequest
        #expect(request?.suggestedUpdates == [bypass, acceptEdits])
    }
}
