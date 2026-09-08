import AppKit

struct OverlayDisplayOption: Identifiable, Equatable {
    static let automaticID = "automatic"

    let id: String
    let title: String
    let subtitle: String
}

enum OverlayPlacementMode: String, Equatable {
    case notch = "Notch area"
    /// A display with no physical notch: the closed island renders as a
    /// floating capsule below the menu bar instead of a pseudo-notch glued
    /// to the physical top edge.
    case floatingPill = "Floating pill fallback"
}

struct OverlayPlacementDiagnostics {
    let targetScreenID: String
    let targetScreenName: String
    let selectionSummary: String
    let mode: OverlayPlacementMode
    let screenFrame: NSRect
    let visibleFrame: NSRect
    let safeAreaInsets: NSEdgeInsets
    let overlayFrame: NSRect

    var targetDescription: String {
        "\(targetScreenName) · \(selectionSummary)"
    }

    var modeDescription: String {
        mode.rawValue
    }

    var screenFrameDescription: String {
        Self.format(screenFrame)
    }

    var visibleFrameDescription: String {
        Self.format(visibleFrame)
    }

    var overlayFrameDescription: String {
        Self.format(overlayFrame)
    }

    var safeAreaDescription: String {
        "top \(Int(safeAreaInsets.top)) · left \(Int(safeAreaInsets.left)) · bottom \(Int(safeAreaInsets.bottom)) · right \(Int(safeAreaInsets.right))"
    }

    private static func format(_ rect: NSRect) -> String {
        let originX = Int(rect.origin.x.rounded())
        let originY = Int(rect.origin.y.rounded())
        let width = Int(rect.size.width.rounded())
        let height = Int(rect.size.height.rounded())
        return "{{\(originX), \(originY)}, {\(width), \(height)}}"
    }
}

enum OverlayDisplayResolver {
    static let defaultPanelSize = NSSize(width: 708, height: 514)

    static func availableDisplayOptions() -> [OverlayDisplayOption] {
        NSScreen.screens.map { screen in
            OverlayDisplayOption(
                id: screenID(for: screen),
                title: screen.localizedName,
                subtitle: "\(screenKindDescription(for: screen)) · \(Int(screen.frame.width))×\(Int(screen.frame.height))"
            )
        }
    }

    static func diagnostics(preferredScreenID: String?, panelSize: NSSize) -> OverlayPlacementDiagnostics? {
        guard let resolvedScreen = resolveScreen(preferredScreenID: preferredScreenID) else {
            return nil
        }

        let screen = resolvedScreen.screen
        let overlayFrame = frame(for: screen, panelSize: panelSize)

        return OverlayPlacementDiagnostics(
            targetScreenID: screenID(for: screen),
            targetScreenName: screen.localizedName,
            selectionSummary: resolvedScreen.selectionSummary,
            mode: placementMode(for: screen),
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaInsets: screen.safeAreaInsets,
            overlayFrame: overlayFrame
        )
    }

    private static func frame(for screen: NSScreen, panelSize: NSSize) -> NSRect {
        pureFrame(
            visibleFrame: screen.visibleFrame,
            screenFrame: screen.frame,
            notchSize: screen.safeAreaInsets.top > 0 ? screen.notchSize : nil,
            panelSize: panelSize,
            mode: placementMode(for: screen)
        )
    }

    /// The overlay placement geometry, with every input passed in rather
    /// than read from `NSScreen` — so a test can exercise both modes without
    /// real display hardware.
    ///
    /// `notchSize` is accepted for parity with the per-mode inputs
    /// `placementMode` already distinguishes on, even though neither branch
    /// below reads it yet — width and the notch-mode height both come from
    /// `panelSize` and `screenFrame` alone.
    static func pureFrame(
        visibleFrame: NSRect,
        screenFrame: NSRect,
        notchSize: NSSize?,
        panelSize: NSSize,
        mode: OverlayPlacementMode
    ) -> NSRect {
        let width = min(panelSize.width, visibleFrame.width - 64)
        let height = panelSize.height
        let x = screenFrame.midX - (width / 2)
        let y = topAnchoredY(screenFrame: screenFrame, visibleFrame: visibleFrame, height: height, mode: mode)

        return NSRect(x: x, y: y, width: width, height: height)
    }

    /// Where a top-anchored overlay's own top edge should sit, in screen
    /// coordinates: flush with the physical top edge for a notched display
    /// (the notch is part of the bezel), or flush with the menu bar's
    /// bottom edge otherwise.
    ///
    /// The single place both `pureFrame` above and the real window frame
    /// (`OverlayPanelController.panelFrame`) get this number from — so a
    /// display with an auto-hidden menu bar (where `visibleFrame.maxY ==
    /// screenFrame.maxY`) can't give the two callers a different answer
    /// than a display with a normal, always-visible one.
    static func topAnchoredY(
        screenFrame: NSRect,
        visibleFrame: NSRect,
        height: CGFloat,
        mode: OverlayPlacementMode
    ) -> CGFloat {
        switch mode {
        case .notch:
            screenFrame.maxY - height
        case .floatingPill:
            visibleFrame.maxY - height
        }
    }

    private static func resolveScreen(preferredScreenID: String?) -> (screen: NSScreen, selectionSummary: String)? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return nil
        }

        if let preferredScreenID,
           let explicitScreen = screens.first(where: { screenID(for: $0) == preferredScreenID }) {
            return (explicitScreen, "manual")
        }

        if preferredScreenID != nil {
            if let notchScreen = screens.first(where: isNotched) {
                return (notchScreen, "manual missing, auto fallback")
            }

            if let mainScreen = NSScreen.main {
                return (mainScreen, "manual missing, main fallback")
            }

            return (screens[0], "manual missing, first-display fallback")
        }

        if let notchScreen = screens.first(where: isNotched) {
            return (notchScreen, "automatic")
        }

        if let mainScreen = NSScreen.main {
            return (mainScreen, "automatic")
        }

        return (screens[0], "automatic")
    }

    private static func placementMode(for screen: NSScreen) -> OverlayPlacementMode {
        isNotched(screen) ? .notch : .floatingPill
    }

    private static func isNotched(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0
            || screen.auxiliaryTopLeftArea?.isEmpty == false
            || screen.auxiliaryTopRightArea?.isEmpty == false
    }

    private static func screenKindDescription(for screen: NSScreen) -> String {
        placementMode(for: screen) == .notch ? "Built-in notch" : "Floating pill fallback"
    }

    /// Returns a string that identifies the physical display backing `screen`
    /// stably across reconnects.
    ///
    /// Uses `CGDisplayCreateUUIDFromDisplayID` so the value survives the
    /// `CGDirectDisplayID` churn that happens on hotplug / sleep / arrangement
    /// changes — without this, a reassigned `CGDirectDisplayID` could silently
    /// route the overlay to a different physical monitor than the one the user
    /// picked. Falls back to a `localizedName + frame` composite when macOS
    /// can't issue a UUID (some AirPlay / virtual displays).
    static func screenID(for screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else {
            return fallbackScreenID(for: screen)
        }

        let displayID = number.uint32Value
        if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
           let cfString = CFUUIDCreateString(nil, uuid) {
            return cfString as String
        }

        return fallbackScreenID(for: screen)
    }

    /// Disambiguates identical displays (e.g. two AirPlay receivers with the
    /// same model name and resolution) by appending the arrangement origin.
    /// The origin is not stable across display rearrangement, but a mismatched
    /// preference will self-heal through the existing
    /// `validSelectionIDs.contains` check in `refreshOverlayDisplayConfiguration()`.
    private static func fallbackScreenID(for screen: NSScreen) -> String {
        let width = Int(screen.frame.width.rounded())
        let height = Int(screen.frame.height.rounded())
        let originX = Int(screen.frame.origin.x.rounded())
        let originY = Int(screen.frame.origin.y.rounded())
        return "fallback-\(screen.localizedName)-\(width)x\(height)@\(originX),\(originY)"
    }
}
