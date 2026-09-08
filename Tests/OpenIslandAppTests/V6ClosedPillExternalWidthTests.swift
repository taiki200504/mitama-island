import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// Exercises `V6ClosedPill.externalIntrinsicWidth(...)` — the floating
/// capsule's content width on a non-notched display. `OverlayPanelController`
/// feeds this exact function into the pill's hit-area width (see
/// `OverlayPanelControllerTests`), so a change here has to be intentional on
/// both sides.
@MainActor
@Suite("Floating pill intrinsic width")
struct V6ClosedPillExternalWidthTests {
    private let height: CGFloat = 30

    @Test("An idle pill with nothing to show reports the bare glyph-plus-padding floor")
    func emptyPillReportsTheBareFloor() {
        let width = V6ClosedPill.externalIntrinsicWidth(
            label: nil, rightSlot: nil, content: nil, sneakPeek: nil, height: height
        )
        // pad*2 (= height) + glyph (24), nothing else showing.
        #expect(width == height + 24)
    }

    @Test("A center label widens the pill")
    func labelWidensThePill() {
        let withoutLabel = V6ClosedPill.externalIntrinsicWidth(
            label: nil, rightSlot: nil, content: nil, sneakPeek: nil, height: height
        )
        let withLabel = V6ClosedPill.externalIntrinsicWidth(
            label: "codex-session", rightSlot: nil, content: nil, sneakPeek: nil, height: height
        )
        #expect(withLabel > withoutLabel)
    }

    @Test("A waiting body suppresses the label instead of stacking beside it")
    func bodySuppressesTheLabelRatherThanAddingToIt() {
        let peek = IslandPeekBand.Content(
            agent: "CODEX",
            subject: .session(.waitingForApproval),
            elapsed: .minutes(8),
            othersWaiting: 0
        )
        let content = IslandClosedContent(body: .waiting(peek))

        let bodyOnly = V6ClosedPill.externalIntrinsicWidth(
            label: nil, rightSlot: nil, content: content, sneakPeek: nil, height: height
        )
        let bodyWithLabel = V6ClosedPill.externalIntrinsicWidth(
            label: "codex-session", rightSlot: nil, content: content, sneakPeek: nil, height: height
        )

        // The label never renders once the body's peek area is showing —
        // reading a session title next to "who is waiting" buries the
        // second in the first — so it must not add any width either.
        #expect(bodyWithLabel == bodyOnly)
    }

    @Test("A right slot widens the pill")
    func rightSlotWidensThePill() {
        let withoutSlot = V6ClosedPill.externalIntrinsicWidth(
            label: nil, rightSlot: nil, content: nil, sneakPeek: nil, height: height
        )
        let withSlot = V6ClosedPill.externalIntrinsicWidth(
            label: nil, rightSlot: .count(3), content: nil, sneakPeek: nil, height: height
        )
        #expect(withSlot > withoutSlot)
    }

    @Test("A non-empty sneak peek widens the pill; an empty one does not")
    func sneakPeekTextDrivesTheWidth() {
        let base = V6ClosedPill.externalIntrinsicWidth(
            label: nil, rightSlot: nil, content: nil, sneakPeek: nil, height: height
        )
        let emptyPeek = IslandSneakPeek(kind: .shelf, text: "", icon: "tray.full", until: .now)
        let withEmptyPeek = V6ClosedPill.externalIntrinsicWidth(
            label: nil, rightSlot: nil, content: nil, sneakPeek: emptyPeek, height: height
        )
        let realPeek = IslandSneakPeek(kind: .shelf, text: "READY TO GO", icon: "tray.full", until: .now)
        let withRealPeek = V6ClosedPill.externalIntrinsicWidth(
            label: nil, rightSlot: nil, content: nil, sneakPeek: realPeek, height: height
        )

        #expect(withEmptyPeek == base)
        #expect(withRealPeek > base)
    }

    @Test("A taller pill widens the floor, since edge padding scales with height")
    func tallerHeightWidensTheFloor() {
        let shortFloor = V6ClosedPill.externalIntrinsicWidth(
            label: nil, rightSlot: nil, content: nil, sneakPeek: nil, height: 30
        )
        let tallFloor = V6ClosedPill.externalIntrinsicWidth(
            label: nil, rightSlot: nil, content: nil, sneakPeek: nil, height: 60
        )
        #expect(tallFloor > shortFloor)
    }

    // MARK: - externalMaxWidth

    @Test("The narrower of the configured panel width and 60% of the visible width wins")
    func maxWidthTakesTheNarrowerBound() {
        // A big screen: the configured panel width (well under 60% of
        // 2,400) is the binding constraint.
        let onABigScreen = V6ClosedPill.externalMaxWidth(
            configuredMaxPanelWidth: 648,
            visibleWidth: 2_400
        )
        #expect(onABigScreen == 648)

        // A small screen: 60% of the visible width undercuts the
        // configured panel width instead.
        let onASmallScreen = V6ClosedPill.externalMaxWidth(
            configuredMaxPanelWidth: 648,
            visibleWidth: 900
        )
        #expect(onASmallScreen == 540)
    }
}
