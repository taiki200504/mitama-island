import AppKit
import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// The opened panel's hit-test rectangle used to be sized purely from the
/// height *estimates* in `OverlayPanelController` (`openedContentHeight` and
/// friends). Change a padding and the estimate drifts from what SwiftUI
/// actually renders, and either the bottom of a card clips or clicks fall
/// through past it. These tests cover the replacement: the estimate is now
/// only the floor, `AppModel.openedSurfaceMeasuredHeight` is the source of
/// truth once it exists, and the result never shrinks mid-transition.
@MainActor
struct OverlayHitRectTests {
    private func makeModel() -> AppModel {
        let name = "overlay-hit-rect-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        let settings = SettingsStore(store: PreferenceStore(suite: suite))
        return AppModel(settings: settings)
    }

    // MARK: - resolveOpenedContentHeight (pure)

    @Test
    func floorWinsWhenMeasurementIsZero() {
        let height = OverlayPanelController.resolveOpenedContentHeight(
            measured: 0,
            estimatedFloor: 240,
            previousStable: 0
        )
        #expect(height == 240)
    }

    @Test
    func floorWinsWhenMeasurementIsSmallerThanTheFloor() {
        // A generous estimate paired with a short first measurement — the
        // estimate must still win so the panel never looks under-filled.
        let height = OverlayPanelController.resolveOpenedContentHeight(
            measured: 80,
            estimatedFloor: 240,
            previousStable: 0
        )
        #expect(height == 240)
    }

    @Test
    func measurementWinsWhenLargerThanTheFloor() {
        // The estimate under-guessed a long question card; the real,
        // measured height must win so the submit button stays reachable.
        let height = OverlayPanelController.resolveOpenedContentHeight(
            measured: 460,
            estimatedFloor: 240,
            previousStable: 0
        )
        #expect(height == 460)
    }

    @Test
    func neverShrinksBelowThePreviousStableValueDuringATransition() {
        // A layout pass mid-spring briefly reports a smaller number than
        // what was already visible a moment ago — the ratchet must hold.
        let height = OverlayPanelController.resolveOpenedContentHeight(
            measured: 120,
            estimatedFloor: 100,
            previousStable: 460
        )
        #expect(height == 460)
    }

    @Test
    func canGrowPastThePreviousStableValue() {
        // Growth is never blocked — only shrinking is.
        let height = OverlayPanelController.resolveOpenedContentHeight(
            measured: 500,
            estimatedFloor: 100,
            previousStable: 300
        )
        #expect(height == 500)
    }

    // MARK: - openedInteractiveRect (pure)

    @Test
    func openedRectIsAnchoredToTheTopOfBounds() {
        let bounds = NSRect(x: 50, y: 10, width: 600, height: 400)
        let rect = OverlayPanelController.openedInteractiveRect(
            in: bounds,
            notchHeight: 32,
            contentHeight: 200,
            horizontalInset: 18,
            bottomInset: 22
        )

        // Top edge matches the bounds' top edge exactly (no gap at the notch).
        let expectedHeight: CGFloat = 232
        let expectedMinX: CGFloat = 68
        let expectedWidth: CGFloat = 564
        #expect(rect.maxY == bounds.maxY)
        #expect(rect.height == expectedHeight)
        #expect(rect.minX == expectedMinX)
        #expect(rect.width == expectedWidth)
    }

    @Test
    func openedRectNeverExceedsTheWindowItHasToWorkWith() {
        // Content height wildly larger than the actual window — the rect
        // must clamp to what the window can offer (minus the bottom shadow
        // inset, which was never clickable), not claim space that doesn't
        // exist and can't be hit-tested anyway.
        let bounds = NSRect(x: 0, y: 0, width: 600, height: 300)
        let rect = OverlayPanelController.openedInteractiveRect(
            in: bounds,
            notchHeight: 32,
            contentHeight: 5_000,
            horizontalInset: 18,
            bottomInset: 22
        )

        let expectedHeight: CGFloat = 278
        #expect(rect.height == expectedHeight)
        #expect(rect.maxY == bounds.maxY)
    }

    // MARK: - interactiveRect (integration: floor + measurement + reset)

    @Test
    func interactiveRectUsesTheFloorBeforeAnyMeasurementExists() {
        let model = makeModel()
        model.notchStatus = .opened
        let controller = OverlayPanelController()
        controller.model = model

        let bounds = NSRect(x: 0, y: 0, width: 648, height: 500)
        let rect = controller.interactiveRect(for: model, in: bounds)

        // No sessions and no measurement yet: falls back to the empty-state
        // floor, not zero — the first frame must still be clickable.
        #expect(rect != nil)
        #expect(rect!.height > 0)
    }

    @Test
    func interactiveRectGrowsToFollowAMeasurementLargerThanTheFloor() {
        let model = makeModel()
        model.notchStatus = .opened
        let controller = OverlayPanelController()
        controller.model = model

        let bounds = NSRect(x: 0, y: 0, width: 648, height: 900)
        let beforeMeasurement = controller.interactiveRect(for: model, in: bounds)!

        model.openedSurfaceMeasuredHeight = beforeMeasurement.height + 200
        let afterMeasurement = controller.interactiveRect(for: model, in: bounds)!

        #expect(afterMeasurement.height > beforeMeasurement.height)
    }

    @Test
    func interactiveRectResetsAfterResetOpenedSurfaceMeasurement() {
        let model = makeModel()
        model.notchStatus = .opened
        let controller = OverlayPanelController()
        controller.model = model

        let bounds = NSRect(x: 0, y: 0, width: 648, height: 900)
        model.openedSurfaceMeasuredHeight = 700
        let tall = controller.interactiveRect(for: model, in: bounds)!
        #expect(tall.height >= 700)

        // Surface change: the coordinator resets both the measurement and
        // the controller's ratchet together (see `OverlayUICoordinator`).
        model.openedSurfaceMeasuredHeight = 0
        controller.resetOpenedSurfaceMeasurement()

        let afterReset = controller.interactiveRect(for: model, in: bounds)!
        #expect(afterReset.height < tall.height)
    }

    @Test
    func closingAndReopeningResetsTheRatchetInsteadOfCarryingTheOldHeightForward() {
        let model = makeModel()
        let controller = OverlayPanelController()
        controller.model = model
        let bounds = NSRect(x: 0, y: 0, width: 648, height: 900)

        model.notchStatus = .opened
        model.openedSurfaceMeasuredHeight = 700
        let tall = controller.interactiveRect(for: model, in: bounds)!
        #expect(tall.height >= 700)

        // Close (observing it at least once decays the ratchet — see
        // `interactiveRect`'s non-opened branch), then reopen with no
        // measurement yet: the old tall value must not leak into the new,
        // possibly much shorter, surface.
        model.notchStatus = .closed
        _ = controller.interactiveRect(for: model, in: bounds)

        model.notchStatus = .opened
        model.openedSurfaceMeasuredHeight = 0
        let afterReopen = controller.interactiveRect(for: model, in: bounds)!

        #expect(afterReopen.height < tall.height)
    }
}
