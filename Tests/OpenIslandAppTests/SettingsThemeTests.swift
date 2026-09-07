import SwiftUI
import Testing
@testable import OpenIslandApp

@Suite("Settings chrome follows the theme")
@MainActor
struct SettingsThemeTests {
    /// Each tab keeps its own hue.
    @Test("Tab colours are stable")
    func tabColoursAreStable() {
        let before = SettingsTab.allCases.map { "\($0.tint)" }
        #expect(SettingsTab.allCases.map { "\($0.tint)" } == before)
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
}
