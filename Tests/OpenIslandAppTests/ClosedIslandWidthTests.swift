import AppKit
import Foundation
import Observation
import Testing
import OpenIslandCore
@testable import OpenIslandApp

@MainActor
struct ClosedIslandWidthTests {
    private func store() -> PreferenceStore {
        PreferenceStore(suite: UserDefaults(suiteName: "closed-width-\(UUID().uuidString)")!)
    }

    @Test func settingPersistsAndNotifiesWithoutChangingOpenedWidth() {
        let store = store()
        let display = DisplaySettings(store: store)
        #expect(display.maxClosedIslandWidth == 280)
        nonisolated(unsafe) var changed = false
        withObservationTracking {
            _ = display.maxClosedIslandWidth
        } onChange: { changed = true }
        display.maxClosedIslandWidth = 96
        #expect(changed)
        #expect(DisplaySettings(store: store).maxClosedIslandWidth == 96)
        #expect(display.maxPanelWidth == 552)
    }

    @Test func invalidPreferencesAreNormalizedWithoutWritingUnrelatedKeys() {
        let store = store()
        store.setValue(712.0, forKey: DisplaySettings.Keys.maxPanelWidth)
        for (raw, safe) in [(Double.nan, 280.0), (.infinity, 280), (-.infinity, 280), (0, 96), (900, 600)] {
            store.setValue(raw, forKey: DisplaySettings.Keys.maxClosedIslandWidth)
            let display = DisplaySettings(store: store)
            #expect(display.maxClosedIslandWidth == safe)
            let persisted: Double = store.value(DisplaySettings.Keys.maxClosedIslandWidth, default: 0)
            #expect(persisted == safe)
            #expect(display.maxPanelWidth == 712)
            display.maxClosedIslandWidth = raw
            #expect(display.maxClosedIslandWidth == safe)
        }
        #expect(Double.nan != Double.nan)
        let clean = self.store()
        _ = DisplaySettings(store: clean)
        #expect(!clean.hasValue(forKey: DisplaySettings.Keys.maxClosedIslandWidth))
    }

    @Test func notchedRenderAndHitWidthShareTheConfiguredCapAndHardwareFloor() {
        let content = IslandClosedContent(body: .waiting(IslandPeekBand.Content(
            agent: "CLAUDE", subject: .session(.waitingForApproval), elapsed: .hours(99), othersWaiting: 9
        )), accessory: .timer(remainingMinutes: 999, label: "Focus"))
        for (notch, cap) in [(180.0, 96.0), (180, 280), (224, 96), (400, 280)] {
            let rendered = V6ClosedPill.macbookLayout(
                content: content, sneakPeek: nil, rightSlot: .count(10),
                physicalNotchWidth: notch, pad: 16, configuredMaxWidth: cap
            )
            let hit = OverlayPanelController.closedPanelWidth(
                notchWidth: notch, isNotchedDisplay: true, notchedContentWidth: rendered.outerWidth,
                maxWidth: cap, notchStatus: .closed
            )
            #expect(hit == rendered.outerWidth)
            #expect(hit >= notch + 66)
            #expect(hit <= max(cap, notch + 66))
            #expect(rendered.compactBody)
            #expect(rendered.accessory == nil)
            #expect((rendered.outerWidth - notch) / 2 >= 33)
        }
    }

    @Test func configuredNotchCapAlsoRespectsMainMaximum() {
        let peek = IslandSneakPeek(kind: .shelf, text: String(repeating: "long", count: 100), icon: "tray", until: .distantFuture)
        let rendered = V6ClosedPill.macbookLayout(
            content: nil, sneakPeek: peek, rightSlot: .count(10),
            physicalNotchWidth: 180, pad: 16, configuredMaxWidth: 600
        )
        #expect(rendered.outerWidth == V6ClosedPill.notchedMaxWidth(physicalNotchWidth: 180))
        let hit = OverlayPanelController.closedPanelWidth(
            notchWidth: 180, isNotchedDisplay: true, notchedContentWidth: rendered.outerWidth,
            maxWidth: 600, notchStatus: .closed
        )
        #expect(hit == rendered.outerWidth)
    }

    @Test func externalWidthAndOldAreaFollowTheSmallerCap() {
        let intrinsic = V6ClosedPill.externalIntrinsicWidth(
            label: String(repeating: "LONG", count: 40), rightSlot: .count(8),
            content: nil, sneakPeek: nil, height: NSScreen.main?.islandClosedHeight ?? 24
        )
        let large = OverlayPanelController.closedPanelWidth(
            notchWidth: 0, isNotchedDisplay: false, intrinsicContentWidth: intrinsic,
            maxWidth: 600, notchStatus: .closed
        )
        let small = OverlayPanelController.closedPanelWidth(
            notchWidth: 0, isNotchedDisplay: false, intrinsicContentWidth: intrinsic,
            maxWidth: 96, notchStatus: .closed
        )
        #expect(large == 600)
        #expect(small == 96)
        let rect = OverlayPanelController.closedSurfaceRect(notchRect: NSRect(x: -10, y: 0, width: 20, height: 28), closedWidth: small)
        #expect(!rect.contains(NSPoint(x: large / 2 - 1, y: 14)))
        #expect(V6ClosedPill.externalMaxWidth(configuredMaxClosedIslandWidth: 600, visibleWidth: 500) == 300)
    }

    @Test func closedTransitionAndDragMousePolicyPassesClearAreas() {
        for status in [NotchStatus.closed, .popping, .opened] {
            for drag in [false, true] {
                #expect(OverlayPanelController.shouldIgnoreMouseEvents(status: status, insideVisibleSurface: false, carryingFiles: drag))
            }
        }
        #expect(OverlayPanelController.shouldIgnoreMouseEvents(status: .closed, insideVisibleSurface: true, carryingFiles: false))
        #expect(!OverlayPanelController.shouldIgnoreMouseEvents(status: .closed, insideVisibleSurface: true, carryingFiles: true))
        #expect(!OverlayPanelController.shouldIgnoreMouseEvents(status: .opened, insideVisibleSurface: true, carryingFiles: false))
        #expect(OverlayPanelController.shouldIgnoreMouseEvents(status: .opened, insideVisibleSurface: true, carryingFiles: false, openingTransition: true))
        #expect(!OverlayPanelController.shouldIgnoreMouseEvents(status: .opened, insideVisibleSurface: true, carryingFiles: true, openingTransition: true))
        #expect(OverlayPanelController.shouldIgnoreMouseEvents(status: .opened, insideVisibleSurface: false, carryingFiles: true, openingTransition: true))
        let pill = NSRect(x: 0, y: 0, width: 96, height: 28)
        #expect(!OverlayPanelController.pointIsInVisibleSurface(NSPoint(x: 0, y: 0), rect: pill, isNotched: false, opened: false))
        #expect(OverlayPanelController.pointIsInVisibleSurface(NSPoint(x: 48, y: 14), rect: pill, isNotched: false, opened: false))
    }

    @Test func realClosedWindowShrinksAndReleasesTheOldFrameImmediately() throws {
        _ = NSApplication.shared
        let settings = SettingsStore(store: store())
        let model = isolatedAppModel(settings: settings)
        model.disablesOverlayEventMonitoringDuringHarness = true
        model.loadDebugSnapshot(IslandDebugScenario.closedFloating.snapshot(), presentOverlay: false)
        let controller = model.overlay.overlayPanelController
        let existing = Set(NSApp.windows.map(\.windowNumber))
        settings.display.maxClosedIslandWidth = 600
        controller.ensurePanel(model: model, preferredScreenID: nil)
        let panel = try #require(NSApp.windows.first { !existing.contains($0.windowNumber) && $0 is NSPanel })
        defer { panel.contentView = nil; panel.close() }
        let old = panel.frame
        settings.display.maxClosedIslandWidth = 96
        _ = controller.reposition(preferredScreenID: nil)
        #expect(panel.frame.width == 96)
        #expect(panel.frame.height == panel.screen?.islandClosedHeight)
        #expect(panel.frame.maxY == panel.screen?.frame.maxY)
        #expect(panel.ignoresMouseEvents)
        #expect(!controller.isPointInClosedSurfaceArea(NSPoint(x: old.maxX - 1, y: old.midY)))
        model.notchOpen(reason: .click)
        _ = controller.show(model: model, preferredScreenID: nil)
        controller.updateMousePassthrough(at: NSPoint(x: panel.frame.minX + 1, y: panel.frame.minY + 1))
        #expect(panel.ignoresMouseEvents)
        model.notchClose()
        controller.setInteractive(false)
        #expect(panel.ignoresMouseEvents)
    }
    @Test func actualFileDragDuringOpeningAdmitsOnlyVisibleSurfaceAndEndsOnMouseUp() throws {
        _ = NSApplication.shared
        let model = isolatedAppModel(settings: SettingsStore(store: store()))
        model.disablesOverlayEventMonitoringDuringHarness = true
        model.loadDebugSnapshot(IslandDebugScenario.closedFloating.snapshot(), presentOverlay: false)
        let controller = model.overlay.overlayPanelController
        let existing = Set(NSApp.windows.map(\.windowNumber))
        controller.ensurePanel(model: model, preferredScreenID: nil)
        let panel = try #require(NSApp.windows.first { !existing.contains($0.windowNumber) && $0 is NSPanel })
        defer { panel.close() }
        model.notchOpen(reason: .click)
        _ = controller.show(model: model, preferredScreenID: nil)
        controller.setInteractive(true)
        let openedFrame = panel.frame
        let inside = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let outside = NSPoint(x: panel.frame.maxX + 10, y: panel.frame.midY)
        let board = NSPasteboard(name: .drag)
        board.clearContents()
        defer { board.clearContents() }
        controller.handleMouseDragged(inside)
        #expect(panel.ignoresMouseEvents)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("opening-drag-\(UUID().uuidString).txt")
        try Data("owned integration fixture".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(board.writeObjects([file as NSURL]))
        controller.handleMouseDragged(inside)
        #expect(!panel.ignoresMouseEvents)
        #expect(panel.frame == openedFrame)
        controller.handleMouseDragged(outside)
        #expect(panel.ignoresMouseEvents)
        controller.handleMouseDragged(inside)
        #expect(!panel.ignoresMouseEvents)
        controller.endClosedDropTargeting()
        #expect(panel.ignoresMouseEvents)
    }

}
