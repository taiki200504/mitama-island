import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
@Suite("Closed content width")
struct IslandClosedContentWidthTests {
    /// A body long enough that nothing else in practice is longer: a
    /// two-digit hour count, the maximum single-digit-plus overflow for
    /// "others waiting", and a timer accessory on top of it.
    private func longestContent() -> IslandClosedContent {
        let peek = IslandPeekBand.Content(
            agent: "CLAUDE",
            subject: .session(.waitingForApproval),
            elapsed: .hours(99),
            othersWaiting: 9
        )
        return IslandClosedContent(
            body: .waiting(peek),
            accessory: .timer(remainingMinutes: 999, label: "Focus")
        )
    }

    @Test("The longest realistic case fits inside the notch width plus its bleed")
    func longestCaseFitsNotchBudget() {
        // A typical physical notch (≈180pt) plus 33pt of bleed on each side —
        // the same budget `OverlayPanelController.closedPillSideBleed` reserves.
        let maxWidth: CGFloat = 180 + 66
        let width = longestContent().intrinsicWidth(layout: .macbook, maxWidth: maxWidth)
        #expect(width <= maxWidth)
    }

    @Test("With no ceiling, the accessory adds real width")
    func accessoryAddsWidthWhenThereIsRoom() {
        let withAccessory = longestContent()
        var bodyOnly = withAccessory
        bodyOnly.accessory = nil

        let withAccessoryWidth = withAccessory.intrinsicWidth(layout: .external)
        let bodyOnlyWidth = bodyOnly.intrinsicWidth(layout: .external)
        #expect(withAccessoryWidth > bodyOnlyWidth)
    }

    @Test("The accessory is the first thing dropped when the two don't fit together")
    func accessoryDroppedFirstWhenTooNarrow() {
        let withAccessory = longestContent()
        var bodyOnly = withAccessory
        bodyOnly.accessory = nil
        let bodyOnlyWidth = bodyOnly.intrinsicWidth(layout: .macbook)

        // A ceiling that fits the body alone but not the body plus the
        // accessory: the accessory must be the one that gives way, not the
        // waiting agent it would otherwise crowd out.
        let resolvedWidth = withAccessory.intrinsicWidth(layout: .macbook, maxWidth: bodyOnlyWidth)
        #expect(resolvedWidth == bodyOnlyWidth)
    }

    @Test("Nothing to show is zero width")
    func emptyContentIsZeroWidth() {
        #expect(IslandClosedContent().intrinsicWidth(layout: .external) == 0)
    }
}
