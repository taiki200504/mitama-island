import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// Exercises `V6ClosedPill.macbookLayout(...)` directly rather than a
/// standalone width helper on `IslandClosedContent` — the accessory-drop
/// decision has to be checked against the pill's real rendered width
/// (leading glyph, padding, and gaps included, not just the body and
/// accessory's own sizes), and the only way to guarantee the check and the
/// render can never disagree is to test the exact function `macbookBody`
/// calls for both.
///
/// The symmetric two-sided macbook pill already routinely grows past
/// `physicalNotchWidth + 66` on the body alone (a long agent name plus a
/// real elapsed time, doubled for both sides of the notch) — that's an
/// existing, accepted shape, not a regression these tests are chasing.
/// What they check is narrower: the accessory never becomes the *reason*
/// the pill is wider than the body alone would already require.
@MainActor
@Suite("Closed content width")
struct IslandClosedContentWidthTests {
    /// The pill's own default height (32) halved — matches what
    /// `V6ClosedPill.pad` computes at its default height.
    private let pad: CGFloat = 16

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

    @Test("A long body already dominates the width, so its accessory rides along for free")
    func longestCaseAccessoryAddsNoExtraWidth() {
        let withAccessory = longestContent()
        var bodyOnly = withAccessory
        bodyOnly.accessory = nil

        let physicalNotchWidth: CGFloat = 180
        let bodyOnlyResult = V6ClosedPill.macbookLayout(
            content: bodyOnly, sneakPeek: nil, rightSlot: nil,
            physicalNotchWidth: physicalNotchWidth, pad: pad
        )
        let withAccessoryResult = V6ClosedPill.macbookLayout(
            content: withAccessory, sneakPeek: nil, rightSlot: nil,
            physicalNotchWidth: physicalNotchWidth, pad: pad
        )

        #expect(withAccessoryResult.accessory != nil)
        #expect(withAccessoryResult.outerWidth == bodyOnlyResult.outerWidth)
    }

    @Test("The accessory survives when there's plainly enough room")
    func accessoryKeptWhenThereIsRoom() {
        let content = IslandClosedContent(accessory: .timer(remainingMinutes: 12, label: "Focus"))
        let result = V6ClosedPill.macbookLayout(
            content: content, sneakPeek: nil, rightSlot: nil,
            physicalNotchWidth: 400, pad: pad
        )
        #expect(result.accessory != nil)
    }

    @Test("The accessory is the one dropped when it would be the reason the pill grows")
    func accessoryDroppedWhenItWouldWidenThePill() {
        // No body, so nothing else is claiming width — a big enough
        // accessory on a narrow enough notch has nowhere to hide.
        let content = IslandClosedContent(accessory: .shelf(count: 999_999_999))
        let physicalNotchWidth: CGFloat = 40

        let bodyOnlyResult = V6ClosedPill.macbookLayout(
            content: IslandClosedContent(), sneakPeek: nil, rightSlot: nil,
            physicalNotchWidth: physicalNotchWidth, pad: pad
        )
        let result = V6ClosedPill.macbookLayout(
            content: content, sneakPeek: nil, rightSlot: nil,
            physicalNotchWidth: physicalNotchWidth, pad: pad
        )

        #expect(result.accessory == nil)
        // Dropping it has to actually shrink the pill back to what nothing
        // showing would already need — not leave some of the extra width in.
        #expect(result.outerWidth == bodyOnlyResult.outerWidth)
    }

    @Test("A competing right slot can push the accessory out even without a body")
    func rightSlotCanCrowdTheAccessoryOut() {
        let content = IslandClosedContent(accessory: .shelf(count: 9))
        let physicalNotchWidth: CGFloat = 180

        let withoutRightSlot = V6ClosedPill.macbookLayout(
            content: content, sneakPeek: nil, rightSlot: nil,
            physicalNotchWidth: physicalNotchWidth, pad: pad
        )
        let withRightSlot = V6ClosedPill.macbookLayout(
            content: content, sneakPeek: nil, rightSlot: .count(9),
            physicalNotchWidth: physicalNotchWidth, pad: pad
        )

        #expect(withoutRightSlot.accessory != nil)
        // Losing to the right slot is fine; growing the pill because of it
        // is not — the accessory gives way instead.
        #expect(withRightSlot.accessory == nil)
        #expect(withRightSlot.outerWidth == withoutRightSlot.outerWidth)
    }

    @Test("A sneak peek's own text width feeds into the pill's total width, the same as a body would")
    func sneakPeekWidthCountsTowardTheTotal() {
        let shortPeek = IslandSneakPeek(kind: .shelf, text: "x", icon: "tray.full", until: .now)
        let longPeek = IslandSneakPeek(kind: .shelf, text: "READY TO GO RIGHT NOW", icon: "tray.full", until: .now)

        let shortResult = V6ClosedPill.macbookLayout(
            content: nil, sneakPeek: shortPeek, rightSlot: nil,
            physicalNotchWidth: 180, pad: pad
        )
        let longResult = V6ClosedPill.macbookLayout(
            content: nil, sneakPeek: longPeek, rightSlot: nil,
            physicalNotchWidth: 180, pad: pad
        )

        #expect(longResult.outerWidth > shortResult.outerWidth)
    }

    @Test("A sneak peek with text suppresses the accessory — only the peek message shows on the left")
    func sneakPeekWithTextSuppressesTheAccessory() {
        let sneakPeek = IslandSneakPeek(kind: .shelf, text: "READY", icon: "tray.full", until: .now)
        let content = IslandClosedContent(accessory: .timer(remainingMinutes: 12, label: "Focus"))
        let result = V6ClosedPill.macbookLayout(
            content: content, sneakPeek: sneakPeek, rightSlot: nil,
            physicalNotchWidth: 400, pad: pad
        )
        #expect(result.accessory == nil)
    }

    @Test("Empty sneak-peek text claims no width and does not suppress the accessory")
    func emptySneakPeekTextDoesNotSuppressTheAccessory() {
        let sneakPeek = IslandSneakPeek(kind: .shelf, text: "", icon: "tray.full", until: .now)
        let content = IslandClosedContent(accessory: .timer(remainingMinutes: 12, label: "Focus"))
        let result = V6ClosedPill.macbookLayout(
            content: content, sneakPeek: sneakPeek, rightSlot: nil,
            physicalNotchWidth: 400, pad: pad
        )
        #expect(result.accessory != nil)
    }

    @Test("With nothing to show, the pill still reports the bare glyph floor")
    func emptyContentReportsTheBareFloor() {
        let result = V6ClosedPill.macbookLayout(
            content: nil, sneakPeek: nil, rightSlot: nil,
            physicalNotchWidth: 180, pad: pad
        )
        #expect(result.accessory == nil)
        // leftContent = 24 (glyph only); halfReserve = max(44, pad + 24 + 6).
        let expectedHalfReserve = max(44, pad + 24 + 6)
        #expect(result.outerWidth == expectedHalfReserve * 2 + 180)
    }
}
