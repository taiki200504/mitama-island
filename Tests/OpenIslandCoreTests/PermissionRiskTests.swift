import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Permission risk")
struct PermissionRiskTests {
    @Test("Looking is ordinary")
    func readOnlyToolsAreOrdinary() {
        for tool in ["Read", "Grep", "Glob", "WebSearch", "TodoWrite"] {
            #expect(PermissionRisk.of(toolName: tool) == .ordinary, "\(tool)")
        }
    }

    @Test("Changing the machine is elevated")
    func writingToolsAreElevated() {
        for tool in ["Bash", "Write", "Edit", "NotebookEdit", "KillShell"] {
            #expect(PermissionRisk.of(toolName: tool) == .elevated, "\(tool)")
        }
    }

    /// A new agent's new tool must not arrive pre-trusted.
    @Test("An unknown tool is elevated")
    func unknownToolsAreElevated() {
        #expect(PermissionRisk.of(toolName: "SomethingBrandNew") == .elevated)
        #expect(PermissionRisk.of(toolName: nil) == .elevated)
        #expect(PermissionRisk.of(toolName: "  ") == .elevated)
    }

    @Test("MCP tools are judged by their last segment")
    func mcpToolsUseTheLeaf() {
        #expect(PermissionRisk.of(toolName: "mcp__notion__read") == .ordinary)
        #expect(PermissionRisk.of(toolName: "mcp__supabase__execute") == .elevated)
    }

    @Test("Case and padding do not change the answer")
    func namesAreNormalised() {
        #expect(PermissionRisk.of(toolName: "  bash ") == .elevated)
        #expect(PermissionRisk.of(toolName: "READ") == .ordinary)
    }
}

@Suite("Voice approval gate")
struct VoiceApprovalGateTests {
    private let now = Date(timeIntervalSince1970: 10_000)

    /// A misheard yes on a file read costs a moment; it is not worth a second
    /// question every time.
    @Test("An ordinary request goes through on the first yes")
    func ordinaryNeedsNoConfirmation() {
        let needs = VoiceApprovalGate.needsSecondSay(
            risk: .ordinary, pending: nil, sessionID: "a", now: now
        )
        #expect(needs == false)
    }

    @Test("An elevated request is held back the first time")
    func elevatedIsHeldBack() {
        let needs = VoiceApprovalGate.needsSecondSay(
            risk: .elevated, pending: nil, sessionID: "a", now: now
        )
        #expect(needs)
    }

    @Test("Saying it again inside the window lets it through")
    func secondSayPasses() {
        let pending = VoiceApprovalGate.Pending(sessionID: "a", askedAt: now)
        let needs = VoiceApprovalGate.needsSecondSay(
            risk: .elevated, pending: pending, sessionID: "a", now: now.addingTimeInterval(5)
        )
        #expect(needs == false)
    }

    /// A yes said to something else entirely, minutes later, must not land here.
    @Test("The window expires")
    func windowExpires() {
        let pending = VoiceApprovalGate.Pending(sessionID: "a", askedAt: now)
        let late = now.addingTimeInterval(VoiceApprovalGate.confirmationWindow + 1)
        let needs = VoiceApprovalGate.needsSecondSay(
            risk: .elevated, pending: pending, sessionID: "a", now: late
        )
        #expect(needs)
    }

    /// Confirmation belongs to the card it was asked about, not to the user.
    @Test("A confirmation for one card does not release another")
    func pendingIsPerCard() {
        let pending = VoiceApprovalGate.Pending(sessionID: "a", askedAt: now)
        let needs = VoiceApprovalGate.needsSecondSay(
            risk: .elevated, pending: pending, sessionID: "b", now: now.addingTimeInterval(1)
        )
        #expect(needs)
    }
}
