import Testing
@testable import OpenIslandApp

@Suite("Menu bar layout preset")
struct MenuBarLayoutTests {
    @Test("Clean keeps the closed island quiet")
    func cleanIsQuiet() {
        #expect(MenuBarLayout.clean.centerLabel == .off)
        #expect(MenuBarLayout.clean.rightSlot == .count)
    }

    @Test("Detailed says what each agent is doing")
    func detailedIsVerbose() {
        #expect(MenuBarLayout.detailed.centerLabel == .agentAction)
        #expect(MenuBarLayout.detailed.rightSlot == .agents)
    }

    /// The preset stores nothing of its own, so applying it and reading it back
    /// has to agree — otherwise the picker would show a value nobody chose.
    @Test("Applying a preset reads back as that preset", arguments: MenuBarLayout.allCases)
    func roundTrips(_ layout: MenuBarLayout) {
        let resolved = MenuBarLayout.resolved(
            rightSlot: layout.rightSlot,
            centerLabel: layout.centerLabel
        )
        #expect(resolved == layout)
    }

    /// Hand-tuned combinations still have to land on one of the two presets.
    @Test("Any finer combination still resolves")
    func resolvesArbitraryCombinations() {
        for slot in IslandRightSlot.allCases {
            for label in IslandCenterLabel.allCases {
                let resolved = MenuBarLayout.resolved(rightSlot: slot, centerLabel: label)
                #expect(resolved == (label == .off ? .clean : .detailed))
            }
        }
    }
}
