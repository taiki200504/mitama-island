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

    /// Granting a permission is the wrong place to make someone parse a second
    /// vocabulary, so these two stay in plain language in both themes.
    @Test("Approval buttons never take on the HUD vocabulary")
    func approvalButtonsStayPlain() {
        withTheme(.hud) {
            let allow = LanguageManager.shared.t("approval.allowOnce")
            let deny = LanguageManager.shared.t("approval.deny")
            #expect(allow != "ACCEPT")
            #expect(deny != "REJECT")
            #expect(allow != allow.uppercased() || allow.count <= 3)
        }
    }
}
