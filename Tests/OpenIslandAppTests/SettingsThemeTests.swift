import SwiftUI
import Testing
@testable import OpenIslandApp

@Suite("Settings chrome follows the theme")
@MainActor
struct SettingsThemeTests {
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

    /// Each tab keeps its own hue in both themes. The HUD only changes how that
    /// hue is applied — a lit glyph rather than a filled block — so the sidebar
    /// stays as easy to scan.
    @Test("Tab colours survive the theme change")
    func tabColoursAreStable() {
        let before = SettingsTab.allCases.map { "\($0.tint)" }
        withTheme(.hud) {
            #expect(SettingsTab.allCases.map { "\($0.tint)" } == before)
        }
        withTheme(.classic) {
            #expect(SettingsTab.allCases.map { "\($0.tint)" } == before)
        }
    }

    /// Two tabs sharing a colour would make the sidebar harder to scan, not
    /// easier — the chip is the fastest thing to recognise in it.
    @Test("Tabs in a section do not share a colour")
    func sectionColoursAreDistinct() {
        for section in SettingsSection.allCases {
            let tints = section.tabs.map { "\($0.tint)" }
            #expect(Set(tints).count == tints.count, "\(section) reuses a colour")
        }
    }

    @Test("The chip follows the theme's corner style")
    func chipFollowsCornerStyle() {
        withTheme(.hud) {
            #expect(IslandThemes.current.cornerStyle == .chamfered)
        }
        withTheme(.classic) {
            #expect(IslandThemes.current.cornerStyle == .rounded)
        }
    }
}
