import Foundation
import Testing
@testable import OpenIslandApp

@Suite("SAO wording", .serialized)
@MainActor
struct SAOVoiceTests {
    private func withLanguage(_ language: LanguageManager.AppLanguage, _ body: () -> Void) {
        let previous = LanguageManager.shared.language
        LanguageManager.shared.language = language
        defer { LanguageManager.shared.language = previous }
        body()
    }

    @Test("The SAO theme speaks in its own vocabulary")
    func saoSpeaksSAO() {
        #expect(LanguageManager.shared.t("banner.completed") == "CONGRATULATIONS")
        #expect(LanguageManager.shared.t("island.sessionOverview.running") == "DIVING")
        #expect(LanguageManager.shared.t("island.sessionOverview.waiting") == "SYSTEM CALL")
        #expect(LanguageManager.shared.t("setup.banner.noHooks.title") == "LINK START")
    }

    /// The words are the system's, not the reader's language. Japanese and
    /// Chinese see the same English the show puts on screen.
    @Test("A themed voice reads the same in every language")
    func themedVoiceIgnoresLanguage() {
        for language in [LanguageManager.AppLanguage.en, .ja, .zhHans] {
            withLanguage(language) {
                #expect(LanguageManager.shared.t("banner.completed") == "CONGRATULATIONS")
            }
        }
    }

    /// The scope is exactly the set of variants that were written. A key with no
    /// `.sao` entry must come back unchanged rather than as its own key name —
    /// the fallback is what keeps this from leaking into the settings panes.
    @Test("A key with no variant is untouched")
    func untouchedWithoutAVariant() {
        let plain = LanguageManager.shared.t("settings.general.diagnostics")
        #expect(!plain.isEmpty)
        #expect(!plain.hasSuffix(".sao"))
        #expect(plain != "settings.general.diagnostics")
    }

    /// The approval pair speaks the SAO vocabulary too. The one property that
    /// must hold: the two must never be easy to mistake for one another,
    /// because this is the button that grants a permission.
    @Test("Approval buttons stay unmistakable")
    func approvalButtonsStayDistinct() {
        let allow = LanguageManager.shared.t("approval.allowOnce")
        let deny = LanguageManager.shared.t("approval.deny")
        #expect(!allow.isEmpty)
        #expect(!deny.isEmpty)
        #expect(allow != deny)
        // Not merely different — different from the first character, so a
        // glance never lands on the wrong one.
        #expect(allow.first != deny.first)
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
