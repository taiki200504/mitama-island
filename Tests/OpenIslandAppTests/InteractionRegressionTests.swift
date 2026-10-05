import AppKit
import Foundation
import Testing
import OpenIslandCore
@testable import OpenIslandApp

@MainActor
struct InteractionRegressionTests {
    private func makeModel(jump: @escaping @Sendable (JumpTarget) throws -> String = { _ in "jumped" }) -> AppModel {
        let suite = UserDefaults(suiteName: "interaction-\(UUID().uuidString)")!
        return isolatedAppModel(terminalJumpAction: jump, settings: SettingsStore(store: PreferenceStore(suite: suite)))
    }

    private func session(_ id: String) -> AgentSession {
        AgentSession(id: id, title: id, tool: .claudeCode, origin: .live, attachmentState: .attached,
                     phase: .running, summary: "Running", updatedAt: .now,
                     jumpTarget: JumpTarget(terminalApp: "Ghostty", workspaceName: id, paneTitle: id))
    }

    @Test func zeroAndOneSessionOpenTheListWithoutStartingAJump() {
        for count in 0...1 {
            let model = makeModel(jump: { _ in Issue.record("Opening the list must not jump"); return "unexpected" })
            model.state = SessionState(sessions: count == 0 ? [] : [session("one")])
            model.toggleSwitcher(reversed: false)
            #expect(model.notchStatus == .opened)
            #expect(!model.switcher.isActive)
            #expect(model.islandSurface == .sessionList())
        }
    }

    @Test func switcherUsesTheSameFilteredRowsAsTheIslandList() {
        let model = makeModel()
        model.settings.notificationFilters.addRule(SilenceRule(field: .workingDirectory, match: .equals, pattern: "/hidden"))
        var hidden = session("hidden")
        hidden.jumpTarget?.workingDirectory = "/hidden"
        model.state = SessionState(sessions: [session("one"), session("two"), hidden])
        model.toggleSwitcher(reversed: false)
        #expect(model.switcher.isActive)
        var highlights: Set<String> = []
        for _ in 0..<6 {
            if let id = model.switcher.highlightedID { highlights.insert(id) }
            model.switcherMoveSelection(reversed: false)
        }
        #expect(highlights == Set(model.islandListSessions.map(\.id)))
        #expect(!highlights.contains("hidden"))
    }

    @Test func explicitJumpShortcutWorksForRunningSessionWithClickJumpDisabled() async throws {
        final class Targets: @unchecked Sendable {
            private let lock = NSLock()
            private var storage: [String] = []
            func append(_ value: String) { lock.lock(); defer { lock.unlock() }; storage.append(value) }
            var ids: [String] { lock.lock(); defer { lock.unlock() }; return storage }
        }
        let targets = Targets()
        let model = makeModel(jump: { target in targets.append(target.paneTitle); return "jumped" })
        model.settings.behaviour.disableClickToJump = true
        model.state = SessionState(sessions: [session("running")])
        model.selectedSessionID = "running"
        model.performShortcut(.jumpToTerminal)
        try await Task.sleep(for: .milliseconds(200))
        #expect(targets.ids == ["running"])
    }

    @Test func disabledUpdaterCannotStartOrOfferAManualUpdateInAnyBuild() {
        for feed in [nil, "", "  ", "http://example.com/feed.xml", "https://user:password@example.com/feed.xml"] {
            let updater = UpdateChecker(feedURL: feed)
            #expect(!updater.isEnabled)
            updater.startIfNeeded()
            updater.checkForUpdates()
            #expect(!updater.canCheckForUpdates)
            #expect(!updater.hasUpdate)
        }
    }
}

@MainActor
struct OverlayPreferredScreenRegressionTests {
    @Test func configuredScreenIsUsedByCurrentScreenAndHitTestingResolver() {
        let controller = OverlayPanelController()
        for screen in NSScreen.screens {
            let id = OverlayDisplayResolver.screenID(for: screen)
            _ = controller.reposition(preferredScreenID: id)
            #expect(controller.currentOverlayScreen.map(OverlayDisplayResolver.screenID(for:)) == id)
        }
    }
}
