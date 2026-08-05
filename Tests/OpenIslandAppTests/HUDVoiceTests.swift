import Foundation
import Testing
@testable import OpenIslandApp

@Suite("HUD wording", .serialized)
@MainActor
struct HUDVoiceTests {
    private func withTheme(_ id: IslandThemeID, _ body: () -> Void) {
        let key = DisplaySettings.Keys.theme
        let previous = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.set(id.rawValue, forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        body()
    }

    @Test("The HUD theme speaks in its own vocabulary")
    func hudSpeaksHUD() {
        withTheme(.hud) {
            #expect(LanguageManager.shared.t("banner.completed") == "QUEST COMPLETE")
            #expect(LanguageManager.shared.t("island.sessionOverview.running") == "ACTIVE")
        }
    }

    @Test("The classic theme keeps plain language")
    func classicStaysPlain() {
        withTheme(.classic) {
            #expect(LanguageManager.shared.t("banner.completed") != "QUEST COMPLETE")
            #expect(LanguageManager.shared.t("island.sessionOverview.running") != "ACTIVE")
        }
    }

    /// The scope is exactly the set of variants that were written. A key with no
    /// `.hud` entry must come back unchanged rather than as its own key name —
    /// the fallback is what keeps this from leaking into the settings panes.
    @Test("A key with no variant is untouched")
    func untouchedWithoutAVariant() {
        withTheme(.hud) {
            let plain = LanguageManager.shared.t("settings.general.diagnostics")
            #expect(!plain.isEmpty)
            #expect(!plain.hasSuffix(".hud"))
            #expect(plain != "settings.general.diagnostics")
        }
    }

    /// The approval pair speaks the HUD vocabulary too, at the owner's request.
    /// The one property that must hold either way: the two must never be easy to
    /// mistake for one another, because this is the button that grants a
    /// permission.
    @Test("Approval buttons stay unmistakable in both themes")
    func approvalButtonsStayDistinct() {
        for id in IslandThemeID.allCases {
            withTheme(id) {
                let allow = LanguageManager.shared.t("approval.allowOnce")
                let deny = LanguageManager.shared.t("approval.deny")
                #expect(!allow.isEmpty)
                #expect(!deny.isEmpty)
                #expect(allow != deny, "\(id) makes accept and reject identical")
                // Not merely different — different from the first character, so
                // a glance never lands on the wrong one.
                #expect(allow.first != deny.first, "\(id) starts both with the same letter")
            }
        }
    }

    @Test("The HUD vocabulary reaches the question card")
    func questionCardSpeaksHUD() {
        withTheme(.hud) {
            #expect(LanguageManager.shared.t("question.submit") == "TRANSMIT")
        }
        withTheme(.classic) {
            #expect(LanguageManager.shared.t("question.submit") != "TRANSMIT")
        }
    }
}

@Suite("Application name in strings")
@MainActor
struct ApplicationNameSubstitutionTests {
    /// The bug this closes: the name was written out in every translation, and
    /// the UI went on saying "Open Island" for months after the app shipped as
    /// "Mitama Island".
    @Test("No user-facing string names the old app")
    func noStaleName() {
        for key in [
            "settings.about.quitApp",
            "island.quit.confirmTitle",
            "window.settings",
            "setup.banner.noHooks.title",
        ] {
            let value = LanguageManager.shared.t(key)
            #expect(!value.contains("Open Island"), "\(key) still names the old app")
            #expect(!value.contains("{app}"), "\(key) left its placeholder unfilled")
        }
    }

    @Test("The filled name is the one on the bundle")
    func usesTheBundleName() {
        #expect(LanguageManager.shared.t("settings.about.quitApp")
            .contains(LanguageManager.applicationName))
    }

    /// The credits line names the project this is forked from, which is a fixed
    /// fact and a GPL obligation — it must not be swept up by the rename.
    @Test("Upstream attribution keeps its own name")
    func creditsKeepUpstream() {
        #expect(LanguageManager.shared.t("settings.about.credits.value").contains("Open Island"))
    }
}
