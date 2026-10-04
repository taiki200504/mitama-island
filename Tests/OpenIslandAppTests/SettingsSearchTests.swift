import Testing
@testable import OpenIslandApp

struct SettingsSearchTests {
    @Test
    func emptySearchRestoresAllTwelveCategories() {
        #expect(SettingsTab.matching("  ", labels: [:]) == SettingsTab.allCases)
        #expect(SettingsTab.allCases.count == 12)
    }

    @Test
    func localizedLabelsAndRelatedTermsFindTheCorrectPane() {
        #expect(SettingsTab.matching("表示", labels: [.display: "表示"]) == [.display])
        #expect(SettingsTab.matching("CODEX quota", labels: [:]) == [.usage])
        #expect(SettingsTab.matching("クリップボード", labels: [:]) == [.island])
        #expect(SettingsTab.matching("承認", labels: [:]) == [.notifications])
        #expect(SettingsTab.matching("no-such-setting", labels: [:]).isEmpty)
    }
}
