import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// Filtering decides what the user never sees, so the cost of getting it wrong
/// is a session silently disappearing. These tests pin the matching rules and
/// the point in the pipeline where they apply.
@MainActor
struct NotificationFilterTests {
    private func makeSettings() -> SettingsStore {
        let name = "filters-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return SettingsStore(store: PreferenceStore(suite: suite))
    }

    private func session(
        id: String,
        directory: String = "/tmp/work",
        firstPrompt: String? = nil
    ) -> AgentSession {
        var session = AgentSession(
            id: id,
            title: "Claude · \(id)",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Running",
            updatedAt: Date(timeIntervalSince1970: 9_000),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "work",
                paneTitle: "claude",
                workingDirectory: directory,
                terminalSessionID: "g-\(id)"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                transcriptPath: "/tmp/\(id).jsonl",
                initialUserPrompt: firstPrompt
            )
        )
        session.isProcessAlive = true
        return session
    }

    // MARK: Matching

    @Test
    func prefixContainsAndEqualsBehaveAsNamed() {
        let target = session(id: "a", directory: "/Users/me/scratch/experiments")

        #expect(SilenceRule(field: .workingDirectory, match: .prefix, pattern: "/Users/me").matches(target))
        #expect(!SilenceRule(field: .workingDirectory, match: .prefix, pattern: "scratch").matches(target))
        #expect(SilenceRule(field: .workingDirectory, match: .contains, pattern: "scratch").matches(target))
        #expect(SilenceRule(field: .workingDirectory, match: .equals, pattern: "/Users/me/scratch/experiments").matches(target))
        #expect(!SilenceRule(field: .workingDirectory, match: .equals, pattern: "/Users/me").matches(target))
    }

    /// A rule that misses only because of capitalisation reads as broken.
    @Test
    func matchingIgnoresCase() {
        let target = session(id: "a", directory: "/Users/Me/Scratch")
        #expect(SilenceRule(field: .workingDirectory, match: .contains, pattern: "scratch").matches(target))
    }

    /// An empty pattern would hide everything.
    @Test
    func anEmptyPatternMatchesNothing() {
        let target = session(id: "a")
        #expect(!SilenceRule(field: .workingDirectory, match: .contains, pattern: "").matches(target))
    }

    @Test
    func aMissingSubjectMatchesNothing() {
        let target = session(id: "a", firstPrompt: nil)
        #expect(!SilenceRule(field: .firstPrompt, match: .contains, pattern: "anything").matches(target))
    }

    @Test
    func promptRulesReadTheFirstPrompt() {
        let target = session(id: "a", firstPrompt: "## Memory Writing Agent\nstore this")
        #expect(SilenceRule(field: .firstPrompt, match: .prefix, pattern: "## Memory Writing").matches(target))
    }

    // MARK: Presets

    /// The presets hide sessions an agent starts for its own bookkeeping, which
    /// nobody asked to watch, so they are in force from the start.
    @Test
    func presetsAreInForceFromTheStart() {
        let filters = makeSettings().notificationFilters
        for preset in SilenceRule.presets {
            #expect(filters.isEnabled(preset))
        }
        #expect(filters.activeRules.count == SilenceRule.presets.count)
    }

    @Test
    func enablingAPresetPutsItInForce() {
        let filters = makeSettings().notificationFilters
        let preset = SilenceRule.presets.first { $0.presetKey == "codexMemories" }!

        filters.setEnabled(true, for: preset)
        #expect(filters.isEnabled(preset))
        #expect(filters.isSilenced(session(id: "m", directory: "/Users/me/.codex/memories/x")))
        #expect(!filters.isSilenced(session(id: "n", directory: "/Users/me/work")))

        filters.setEnabled(false, for: preset)
        #expect(!filters.isSilenced(session(id: "m", directory: "/Users/me/.codex/memories/x")))
    }

    @Test
    func everyPresetHasAVisibleLabel() {
        for preset in SilenceRule.presets {
            #expect(LanguageManager.shared.t(preset.presetLabelKey) != preset.presetLabelKey)
        }
    }

    // MARK: Custom rules

    @Test
    func customRulesSurviveANewInstance() {
        let store = makeSettings()
        store.notificationFilters.addRule(
            SilenceRule(field: .workingDirectory, match: .contains, pattern: "/scratch")
        )

        #expect(store.notificationFilters.customRules.count == 1)
        #expect(store.notificationFilters.isSilenced(session(id: "s", directory: "/a/scratch/b")))
    }

    /// A blank pattern would silence the whole list, so it is refused at entry.
    @Test
    func blankRulesAreRefused() {
        let filters = makeSettings().notificationFilters
        filters.addRule(SilenceRule(field: .workingDirectory, match: .contains, pattern: "   "))
        #expect(filters.customRules.isEmpty)
    }

    @Test
    func rulesCanBeRemoved() {
        let filters = makeSettings().notificationFilters
        let rule = SilenceRule(field: .workingDirectory, match: .contains, pattern: "/scratch")
        filters.addRule(rule)
        filters.removeRule(id: rule.id)
        #expect(filters.customRules.isEmpty)
    }

    @Test
    func theLivePreviewCountsWhatWouldBeHidden() {
        let filters = makeSettings().notificationFilters
        let sessions = [
            session(id: "a", directory: "/x/scratch/1"),
            session(id: "b", directory: "/x/scratch/2"),
            session(id: "c", directory: "/x/real"),
        ]
        let candidate = SilenceRule(field: .workingDirectory, match: .contains, pattern: "scratch")
        #expect(filters.matchCount(for: candidate, in: sessions) == 2)
    }

    // MARK: Where filtering applies

    /// Filtering happens before the island's buckets are built, so a hidden
    /// session is absent from the counts too — not merely skipped when drawing.
    @Test
    func aHiddenSessionLeavesTheListAndTheCounts() {
        let settings = makeSettings()
        let model = AppModel(settings: settings)
        model.state = SessionState(sessions: [
            session(id: "visible", directory: "/x/real"),
            session(id: "noisy", directory: "/x/scratch"),
        ])

        #expect(model.islandListSessions.map(\.id).sorted() == ["noisy", "visible"])
        #expect(model.liveSessionCount == 2)

        settings.notificationFilters.addRule(
            SilenceRule(field: .workingDirectory, match: .contains, pattern: "/scratch")
        )

        #expect(model.islandListSessions.map(\.id) == ["visible"])
        #expect(model.liveSessionCount == 1)
    }
}
