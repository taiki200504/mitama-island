import AppKit
import Combine
import SwiftUI
import OpenIslandCore

@MainActor
final class OverlayPanelController {
    // Measured against the reference product: the opened panel reads as a
    // wide, low-density surface (648pt on a 1512pt screen). 540pt forced
    // session titles and tool lines to truncate several words earlier.
    private static let preferredNotchOpenedPanelWidth: CGFloat = 648
    private static let preferredTopBarOpenedPanelWidth: CGFloat = 620
    private static let preferredNotificationPanelWidth: CGFloat = 620
    private static let openedContentWidthPadding: CGFloat = 0
    private static let openedContentBottomPadding: CGFloat = 0
    /// Must match `IslandPanelView.maxSessionListHeight` — the AutoHeightScrollView cap.
    private static let maxSessionListHeight: CGFloat = 560
    private static let maxVisibleSessionRows: Int = 6
    private static let openedRowSpacing: CGFloat = 0
    // Content padding top + scroll padding + v8 list header/footer + bottom inset.
    // Rows are now full-width scan rows, so the old inter-card spacing is gone.
    private static let openedContentVerticalInsets: CGFloat = 84
    /// The gap between what the card measures and the room the panel has to
    /// give it.
    ///
    /// Was 8, and a notification card's last control sat about forty points
    /// below the panel's bottom edge — the shortfall was constant regardless of
    /// how tall the card was, which is what pointed at this number rather than
    /// at any one card's layout. Verified against the `longQuestionCard`
    /// capture in `smoke-all`, where the submit button used to be cut in half.
    private static let notificationMeasuredContentPadding: CGFloat = 48
    private static let notificationEstimatedVerticalInsets: CGFloat = 36
    private static let openedEmptyStateHeight: CGFloat = 108
    private static let questionCardBaseHeight: CGFloat = 110
    /// Tall enough for a full option list at its scroll cap plus the chrome
    /// below it. Anything smaller clips the submit button.
    private static let questionCardMaxHeight: CGFloat = 500
    // Completion card chrome breakdown (everything except the scrollable text):
    // openedContent vertical padding: 24, card container padding: 28,
    // card VStack spacing: 14, card header (title+prompt): ~50,
    // completionBody header ("You:"/Done row): ~42, divider: 1,
    // text area vertical padding: 28  →  total ≈ 187
    private static let completionCardChromeHeight: CGFloat = 187
    private static let completionCardMinHeight: CGFloat = 210
    private static let completionCardMaxHeight: CGFloat = 400

    private var panel: NotchPanel?
    private var eventMonitors = NotchEventMonitors()
    private var hoverTimer: DispatchWorkItem?
    private var hoverCancelGrace: DispatchWorkItem?
    weak var model: AppModel?
    private(set) var notchRect: NSRect = .zero

    var isVisible: Bool {
        panel?.isVisible == true
    }

    nonisolated static func shouldActivatePanel(for reason: NotchOpenReason?) -> Bool {
        reason == .click
    }

    func availableDisplayOptions() -> [OverlayDisplayOption] {
        OverlayDisplayResolver.availableDisplayOptions()
    }

    func ensurePanel(model: AppModel, preferredScreenID: String?) {
        self.model = model
        let panel = self.panel ?? makePanel(model: model)
        self.panel = panel
        positionPanel(panel, preferredScreenID: preferredScreenID, animated: false)
        panel.orderFrontRegardless()
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = false
        startEventMonitoring()
    }

    func show(model: AppModel, preferredScreenID: String?) -> OverlayPlacementDiagnostics? {
        self.model = model
        let panel = self.panel ?? makePanel(model: model)
        self.panel = panel
        let diagnostics = positionPanel(panel, preferredScreenID: preferredScreenID, animated: true)
        presentPanel(panel, activates: Self.shouldActivatePanel(for: model.notchOpenReason))
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        startEventMonitoring()
        return diagnostics
    }

    func hide() {
        panel?.ignoresMouseEvents = true
        panel?.acceptsMouseMovedEvents = false
    }

    func setInteractive(_ interactive: Bool) {
        guard let panel else {
            return
        }

        panel.ignoresMouseEvents = !interactive
        panel.acceptsMouseMovedEvents = interactive

        if interactive {
            presentPanel(panel, activates: Self.shouldActivatePanel(for: model?.notchOpenReason))
        }
    }

    func reposition(preferredScreenID: String?) -> OverlayPlacementDiagnostics? {
        guard let panel else {
            return placementDiagnostics(preferredScreenID: preferredScreenID)
        }

        return positionPanel(panel, preferredScreenID: preferredScreenID, animated: true)
    }

    func placementDiagnostics(preferredScreenID: String?) -> OverlayPlacementDiagnostics? {
        let panelSize = panel?.frame.size ?? OverlayDisplayResolver.defaultPanelSize
        return OverlayDisplayResolver.diagnostics(preferredScreenID: preferredScreenID, panelSize: panelSize)
    }

    // MARK: - Panel creation

    private func makePanel(model: AppModel) -> NotchPanel {
        let screen = resolveTargetScreen() ?? NSScreen.main
        let windowFrame = screen.map { panelFrame(for: model, on: $0) } ?? .zero

        let panel = NotchPanel(
            contentRect: windowFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .statusBar
        panel.sharingType = .readOnly
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = false
        // `.stationary` keeps the overlay pinned during the macOS Sonoma+
        // "click wallpaper to reveal desktop" gesture (and Mission Control
        // / Show Desktop). Without it the panel slides off-screen with the
        // user's other windows — on built-in notch displays it disappears
        // below the menu bar, and on external displays it falls out of the
        // top bar entirely.
        panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .ignoresCycle, .stationary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.ignoresMouseEvents = true

        let hostingView = NotchHostingView(rootView: IslandPanelView(model: model))
        hostingView.notchController = self
        panel.contentView = hostingView

        computeNotchRect(screen: resolveTargetScreen())
        return panel
    }

    // MARK: - Positioning

    @discardableResult
    private func positionPanel(
        _ panel: NSPanel,
        preferredScreenID: String?,
        animated: Bool
    ) -> OverlayPlacementDiagnostics? {
        guard let screen = resolveTargetScreen(preferredScreenID: preferredScreenID) else {
            return nil
        }

        let windowFrame = panelFrame(for: model, on: screen)

        // Always set the panel frame instantly — no AppKit animation.
        // All visual transitions (shape, size, opacity, corner radius) are
        // driven by SwiftUI's .animation() modifier on the content view.
        // Mixing NSAnimationContext with SwiftUI spring animations caused
        // visible jank because the two systems have different timing curves,
        // durations, and start times (AppKit was deferred by one runloop).
        if panel.frame != windowFrame {
            panel.setFrame(windowFrame, display: true)
        }
        computeNotchRect(screen: screen)

        return OverlayDisplayResolver.diagnostics(
            preferredScreenID: preferredScreenID,
            panelSize: panel.frame.size
        )
    }

    private func presentPanel(_ panel: NSPanel, activates: Bool) {
        // "Hide in fullscreen" and "hide when nothing is running" mean the pill
        // itself should be off screen, not merely collapsed.
        guard model?.islandMayBeVisible ?? true else {
            panel.orderOut(nil)
            return
        }

        if activates {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func computeNotchRect(screen: NSScreen?) {
        guard let screen else {
            notchRect = .zero
            return
        }

        let notchSize = screen.notchSize
        let screenFrame = screen.frame
        let notchX = screenFrame.midX - notchSize.width / 2
        let notchY = screenFrame.maxY - notchSize.height
        notchRect = NSRect(x: notchX, y: notchY, width: notchSize.width, height: notchSize.height)
    }

    /// Picks the screen to anchor the overlay to.
    ///
    /// Priority: persisted manual preference (matched via the stable
    /// `OverlayDisplayResolver.screenID` so a hotplug-reassigned
    /// `CGDirectDisplayID` can't silently re-target the wrong monitor) →
    /// first notched screen → `NSScreen.main` → first available screen.
    /// Returns `nil` only when no displays are connected.
    /// The screen the island is currently on, so anything else the app shows
    /// lands where the user is already looking.
    var currentOverlayScreen: NSScreen? { resolveTargetScreen() }

    private func resolveTargetScreen(preferredScreenID: String? = nil) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        if let preferredScreenID,
           let screen = screens.first(where: { OverlayDisplayResolver.screenID(for: $0) == preferredScreenID }) {
            return screen
        }

        if let notchScreen = screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notchScreen
        }

        return NSScreen.main ?? screens[0]
    }

    // MARK: - Mouse event monitoring

    private func startEventMonitoring() {
        if model?.disablesOverlayEventMonitoringDuringHarness == true {
            return
        }

        guard !eventMonitors.isActive else { return }

        eventMonitors.start { [weak self] location in
            self?.handleMouseMoved(location)
        } mouseDownHandler: { [weak self] location in
            self?.handleMouseDown(location)
        } mouseDragHandler: { [weak self] location in
            self?.handleMouseDragged(location)
        }
    }

    private func handleMouseMoved(_ screenLocation: NSPoint) {
        guard let model else { return }

        let inClosedSurfaceArea = isPointInClosedSurfaceArea(screenLocation)

        if model.notchStatus == .closed && inClosedSurfaceArea {
            if model.settings.behaviour.expandOnHover {
                scheduleHoverOpen()
            }
        } else if model.notchStatus == .closed && !inClosedSurfaceArea {
            cancelHoverOpen()
        }

        let shouldTrackNotificationPointer = model.notchStatus == .opened
            && model.notchOpenReason == .notification
            && model.showsNotificationCard

        if shouldTrackNotificationPointer || model.shouldAutoCollapseOnMouseLeave {
            if isPointInExpandedArea(screenLocation) {
                model.notePointerInsideIslandSurface()
            } else {
                model.handlePointerExitedIslandSurface()
            }
        }
    }

    /// Opens the island for a file being dragged towards it.
    ///
    /// The shelf lives inside the opened panel, so without this the only way to
    /// put a file down was to open the island by hand first, let go of the
    /// file, and start the drag again — which is not a thing anyone does.
    ///
    /// Only file drags count. Dragging a window or selecting text near the top
    /// of the screen must not make the island jump out.
    private func handleMouseDragged(_ screenLocation: NSPoint) {
        guard let model, model.notchStatus == .closed else { return }
        guard model.settings.behaviour.expandOnHover else { return }

        guard isPointInClosedSurfaceArea(screenLocation) else {
            cancelHoverOpen()
            return
        }

        guard Self.draggedItemsAreFiles() else { return }

        scheduleHoverOpen()
    }

    /// What the current drag is carrying, if anything. The drag pasteboard is
    /// the only place a cross-application drag announces itself.
    static func draggedItemsAreFiles() -> Bool {
        NSPasteboard(name: .drag).canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
    }

    private func handleMouseDown(_ screenLocation: NSPoint) {
        guard let model else { return }

        let inClosedSurfaceArea = isPointInClosedSurfaceArea(screenLocation)

        if model.notchStatus == .closed && inClosedSurfaceArea {
            cancelHoverOpenImmediately()
            model.notchOpen(reason: .click)
        } else if model.notchStatus == .opened {
            // A card asking for approval or an answer stays put: clicking back
            // into the terminal to read the diff must not throw away the request.
            if !isPointInExpandedArea(screenLocation),
               model.settings.behaviour.dismissOnOutsideClick,
               !model.islandSurfaceAwaitsUserAction {
                model.notchClose()
                repostMouseDown(at: screenLocation)
            }
        }
    }

    /// Grace period before a hover-open timer is cancelled.  Prevents
    /// mouse jitter at the notch edge from resetting the delay.
    private static let hoverCancelGracePeriod: TimeInterval = 0.1

    private func scheduleHoverOpen() {
        // Mouse re-entered during grace period — just revoke the cancel.
        hoverCancelGrace?.cancel()
        hoverCancelGrace = nil

        guard model != nil else { return }

        guard hoverTimer == nil else { return }

        let item = DispatchWorkItem { [weak self] in
            guard let self, let model = self.model else { return }
            self.performHoverOpen(model)
            self.hoverTimer = nil
        }

        hoverTimer = item
        let delay = model?.settings.behaviour.hoverDuration ?? AppModel.hoverOpenDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func performHoverOpen(_ model: AppModel) {
        guard model.notchStatus == .closed else { return }

        if model.hapticFeedbackEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(
                NSHapticFeedbackManager.FeedbackPattern.alignment,
                performanceTime: .now
            )
        }

        model.notchOpen(reason: .hover)
    }

    private func cancelHoverOpen() {
        guard hoverTimer != nil else { return }

        // Don't cancel immediately — allow a short grace period so that
        // mouse jitter at the notch edge doesn't restart the timer.
        guard hoverCancelGrace == nil else { return }

        let grace = DispatchWorkItem { [weak self] in
            self?.hoverTimer?.cancel()
            self?.hoverTimer = nil
            self?.hoverCancelGrace = nil
        }

        hoverCancelGrace = grace
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.hoverCancelGracePeriod,
            execute: grace
        )
    }

    /// Cancel without grace period — used for click-to-open where the
    /// hover timer must not fire after the click already opened the panel.
    private func cancelHoverOpenImmediately() {
        hoverCancelGrace?.cancel()
        hoverCancelGrace = nil
        hoverTimer?.cancel()
        hoverTimer = nil
    }

    // MARK: - Hit testing geometry

    func isPointInClosedSurfaceArea(_ screenPoint: NSPoint) -> Bool {
        guard let model else { return false }

        if let closedSurfaceRect = closedSurfaceRect(for: model) {
            return Self.rectContainsIncludingEdges(closedSurfaceRect, point: screenPoint)
        }

        let expandedNotch = notchRect.insetBy(dx: -20, dy: -10)
        return Self.rectContainsIncludingEdges(expandedNotch, point: screenPoint)
    }

    func isPointInExpandedArea(_ screenPoint: NSPoint) -> Bool {
        guard let model, model.notchStatus == .opened else {
            return isPointInClosedSurfaceArea(screenPoint)
        }

        guard let panel else {
            return false
        }

        // The window is always at opened size, but the visible content area
        // is the inner content rect (excluding shadow insets).
        guard let contentRect = contentRect(for: model, in: panel.frame) else {
            return false
        }

        return Self.rectContainsIncludingEdges(contentRect, point: screenPoint)
    }

    func openedPanelWidth(for screen: NSScreen?) -> CGFloat {
        // A notched display gets the wider surface; the configured width caps
        // both, and the screen itself caps that in turn.
        let configured = model?.settings.display.maxPanelWidth
        guard let screen else {
            return configured.map { CGFloat($0) } ?? Self.preferredTopBarOpenedPanelWidth
        }
        let fallback = screen.safeAreaInsets.top > 0
            ? Self.preferredNotchOpenedPanelWidth
            : Self.preferredTopBarOpenedPanelWidth
        let preferredWidth = configured.map { CGFloat($0) } ?? fallback
        return max(360, min(preferredWidth, screen.visibleFrame.width - 32))
    }

    func notificationPanelWidth(for screen: NSScreen?) -> CGFloat {
        guard let screen else {
            return Self.preferredNotificationPanelWidth
        }

        return min(Self.preferredNotificationPanelWidth, screen.visibleFrame.width - 32)
    }

    func contentRect(for model: AppModel, in bounds: NSRect) -> NSRect? {
        let insets = panelShadowInsets
        return NSRect(
            x: bounds.minX + insets.horizontal,
            y: bounds.minY + insets.bottom,
            width: max(0, bounds.width - (insets.horizontal * 2)),
            height: max(0, bounds.height - insets.bottom)
        )
    }

    nonisolated static func closedSurfaceRect(
        notchRect: NSRect,
        closedWidth: CGFloat
    ) -> NSRect {
        let cx = notchRect.midX
        return NSRect(
            x: cx - closedWidth / 2,
            y: notchRect.minY,
            width: closedWidth,
            height: notchRect.height
        )
    }

    nonisolated static func rectContainsIncludingEdges(_ rect: NSRect, point: NSPoint) -> Bool {
        point.x >= rect.minX
            && point.x <= rect.maxX
            && point.y >= rect.minY
            && point.y <= rect.maxY
    }

    /// Horizontal bleed of the closed pill past each side of the physical
    /// notch. Measured against the reference product at 33pt per side on a
    /// 185pt notch (255pt total); the old 44pt made the pill read as a
    /// separate slab rather than an extension of the notch.
    nonisolated static let closedPillSideBleed: CGFloat = 33

    /// Hit-area width of the closed pill.
    ///
    /// - On a MacBook (physical notch present) the pill is locked to
    ///   `bleed + notchWidth + bleed`.
    /// - On an external display the width is content-driven; we return a
    ///   generous fixed hit-area so hover / click detection works without
    ///   the controller having to introspect live session state.
    nonisolated static func closedPanelWidth(
        notchWidth: CGFloat,
        isNotchedDisplay: Bool,
        notchStatus: NotchStatus
    ) -> CGFloat {
        let popBonus: CGFloat = notchStatus == .popping ? 18 : 0
        if isNotchedDisplay {
            return notchWidth + (closedPillSideBleed * 2) + popBonus
        }
        return 360 + popBonus
    }

    private func closedSurfaceRect(for model: AppModel) -> NSRect? {
        guard let screen = resolveTargetScreen() else {
            return nil
        }

        let closedWidth = closedPanelWidth(for: model, on: screen)
        return Self.closedSurfaceRect(
            notchRect: notchRect,
            closedWidth: closedWidth
        )
    }

    private func panelFrame(for model: AppModel?, on screen: NSScreen) -> NSRect {
        let size = panelSize(for: model, on: screen)
        return NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Always returns the maximum (opened) panel size so the window never
    /// needs to resize.  All visual transitions are driven purely by SwiftUI
    /// inside this fixed-size window.
    private func panelSize(for model: AppModel?, on screen: NSScreen) -> CGSize {
        let insets = panelShadowInsets

        guard let model else {
            return CGSize(
                width: openedPanelWidth(for: screen) + Self.openedContentWidthPadding + (insets.horizontal * 2),
                height: screen.notchSize.height + Self.openedEmptyStateHeight + Self.openedContentBottomPadding + insets.bottom
            )
        }

        let panelWidth = openedPanelWidth(for: screen)
        let contentHeight = openedContentHeight(for: model)
        // Use at least the empty-state height so the window doesn't shrink
        // when sessions come and go while opened.
        let height = screen.notchSize.height + max(contentHeight, Self.openedEmptyStateHeight) + Self.openedContentBottomPadding + insets.bottom

        return CGSize(
            width: panelWidth + Self.openedContentWidthPadding + (insets.horizontal * 2),
            height: height
        )
    }

    /// Constant insets — always opened size since the window never shrinks.
    private var panelShadowInsets: (horizontal: CGFloat, bottom: CGFloat) {
        (
            horizontal: IslandChromeMetrics.openedShadowHorizontalInset,
            bottom: IslandChromeMetrics.openedShadowBottomInset
        )
    }

    private func closedPanelWidth(for model: AppModel, on screen: NSScreen) -> CGFloat {
        let notchWidth = screen.notchSize.width
        let isNotched = screen.safeAreaInsets.top > 0
        return Self.closedPanelWidth(
            notchWidth: notchWidth,
            isNotchedDisplay: isNotched,
            notchStatus: model.notchStatus
        )
    }

    private func openedContentHeight(for model: AppModel) -> CGFloat {
        let now = Date.now
        let visibleSessions = openedVisibleSessions(
            sessions: model.islandListSessions
        )

        if visibleSessions.isEmpty {
            return Self.openedEmptyStateHeight
        }

        let actionableID = model.islandSurface.sessionID
        let isNotificationMode = model.notchOpenReason == .notification && actionableID != nil

        if isNotificationMode {
            // Use SwiftUI-measured height when available (accurate after first render).
            if model.measuredNotificationContentHeight > 0 {
                return model.measuredNotificationContentHeight + Self.notificationMeasuredContentPadding
            }
            // First render: estimate from the actionable session's content so the
            // initial window is close to the final size. This avoids a large blank
            // panel flash (the previous 500pt fallback) and reduces the chance of
            // a measurement→reposition cycle.
            if let actionableID,
               let session = model.state.session(id: actionableID) {
                let rowHeight = session.estimatedIslandRowHeight(at: now)
                let bodyHeight = actionableBodyHeight(for: session, model: model)
                return rowHeight + bodyHeight + Self.notificationEstimatedVerticalInsets
            }
            return 300
        }

        let rowHeights = visibleSessions.map { session -> CGFloat in
            if session.id == actionableID {
                return session.estimatedIslandRowHeight(at: now)
                    + actionableBodyHeight(for: session, model: model)
            }
            return session.estimatedIslandRowHeight(at: now)
        }

        let rowsHeight = rowHeights.reduce(CGFloat.zero, +)
        let spacingHeight = CGFloat(max(0, rowHeights.count - 1)) * Self.openedRowSpacing
        let listHeight = rowsHeight + spacingHeight
        // Cap to match AutoHeightScrollView's maxHeight in IslandPanelView.
        let cappedListHeight = min(listHeight, Self.maxSessionListHeight)
        return cappedListHeight + Self.openedContentVerticalInsets
    }

    /// Additional height for the actionable session's inline action area.
    private func actionableBodyHeight(for session: AgentSession, model: AppModel) -> CGFloat {
        switch session.phase {
        case .waitingForApproval:
            return 118
        case .waitingForAnswer:
            return questionCardHeight(for: session.questionPrompt) - 44
        case .completed:
            return completionBodyHeight(for: session, model: model)
        case .running:
            return 0
        }
    }

    /// Height of the inline completion expansion area (not the old full-card height).
    private func completionBodyHeight(for session: AgentSession, model: AppModel) -> CGFloat {
        let headerHeight: CGFloat = 44

        let text = (session.completionAssistantMessageText ?? session.summary)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            return headerHeight
        }

        let availableWidth = Self.preferredNotificationPanelWidth - 96
        let font = NSFont.systemFont(ofSize: 13.5, weight: .medium)
        let textSize = (text as NSString).boundingRect(
            with: NSSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let markdownHeight = min(260, ceil(textSize.height) + 20)
        // Reply input: divider (1) + input bar padding+content (~52)
        let replyInputHeight: CGFloat = TerminalTextSender.canReply(to: session, enabled: model.completionReplyEnabled) ? 53 : 0
        return headerHeight + 1 + markdownHeight + replyInputHeight
    }

    /// Estimates the question card height based on prompt content (question count,
    /// option count per question, and whether the prompt title is shown).
    private func questionCardHeight(for prompt: QuestionPrompt?) -> CGFloat {
        guard let prompt else {
            return Self.questionCardBaseHeight
        }

        let questions = prompt.questions.isEmpty && !prompt.options.isEmpty
            ? [
                QuestionPromptItem(
                    question: prompt.title,
                    header: "",
                    options: prompt.options.map { QuestionOption(label: $0) }
                ),
            ]
            : prompt.questions

        guard !questions.isEmpty else {
            return Self.questionCardBaseHeight
        }

        // Card chrome: outer padding + submit button.
        // When the prompt title is suppressed (single question whose title
        // matches the question text), reduce chrome because the body carries it.
        let titleSuppressed = questions.count == 1
            && prompt.title == questions.first?.question
        let chromeHeight: CGFloat = titleSuppressed ? 82 : 102
        var listHeight: CGFloat = 0

        for question in questions {
            if questions.count > 1 {
                listHeight += 16 // header
            }
            listHeight += 20 // question text
            for option in question.options {
                listHeight += Self.estimatedOptionRowHeight(for: option.label)
            }
        }

        // Inter-question spacing (only between questions, not after the last).
        listHeight += CGFloat(max(0, questions.count - 1)) * 10

        // The list scrolls past this, so the panel must be sized for the cap
        // rather than for the whole list — otherwise a long question pushes the
        // submit button outside the panel it is supposed to sit in.
        let estimated = chromeHeight + min(listHeight, IslandChromeMetrics.questionOptionListMaxHeight)
        return min(Self.questionCardMaxHeight, max(Self.questionCardBaseHeight, estimated))
    }

    /// How tall one option row will be once its label has wrapped.
    ///
    /// A flat 38pt per row was the old guess. A long option wraps to two or three
    /// lines, so the card was sized for less than it needed and the last options
    /// fell outside it.
    static func estimatedOptionRowHeight(for label: String) -> CGFloat {
        let singleLine: CGFloat = 38
        // Roughly what fits on one line at the option font inside the card.
        let charactersPerLine = 46
        let lines = max(1, Int(ceil(Double(label.count) / Double(charactersPerLine))))
        return singleLine + CGFloat(lines - 1) * 15
    }

    private func completionCardHeight(for model: AppModel) -> CGFloat {
        guard let session = model.activeIslandCardSession else {
            return Self.completionCardMinHeight
        }

        let text = (session.completionAssistantMessageText ?? session.summary)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Estimate text height using NSString measurement with the actual font.
        // Available text width ≈ notificationPanelWidth - card horizontal chrome
        // Card chrome: openedContent padding (18*2) + card padding (16*2) + text padding (14*2) = 96
        let availableWidth = Self.preferredNotificationPanelWidth - 96
        let font = NSFont.systemFont(ofSize: 13.5, weight: .medium)
        let textSize = (text as NSString).boundingRect(
            with: NSSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )

        let estimatedHeight = Self.completionCardChromeHeight + ceil(textSize.height)
        // Use a smaller minimum to avoid blank space when content is short
        let minHeight: CGFloat = Self.completionCardChromeHeight + 20
        let ceiling = CGFloat(model.settings.display.completionCardMaxHeight)
        // The floor wins over a ceiling set below it: a card too short to show
        // its own buttons is worse than one taller than asked for.
        return min(max(ceiling, minHeight), max(minHeight, estimatedHeight))
    }

    private func openedVisibleSessions(sessions: [AgentSession]) -> [AgentSession] {
        Array(sessions.prefix(Self.maxVisibleSessionRows))
    }

    // MARK: - Event reposting

    private func repostMouseDown(at screenPoint: NSPoint) {
        let flippedY = NSScreen.main.map { $0.frame.height - screenPoint.y } ?? screenPoint.y

        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: CGPoint(x: screenPoint.x, y: flippedY),
            mouseButton: .left
        ) else { return }

        event.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            guard let upEvent = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseUp,
                mouseCursorPosition: CGPoint(x: screenPoint.x, y: flippedY),
                mouseButton: .left
            ) else { return }
            upEvent.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - NotchPanel

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - NotchHostingView

final class NotchHostingView<Content: View>: NSHostingView<Content> {
    weak var notchController: OverlayPanelController?

    override var isOpaque: Bool {
        false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        // Ensure the panel is key before SwiftUI processes the click.
        // With nonactivatingPanel, hover-opened panels aren't key, so
        // SwiftUI Button may consume the first click for key acquisition
        // instead of firing its action.
        window?.makeKey()
        super.mouseDown(with: event)
    }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        configureTransparency()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let controller = notchController,
              let model = controller.model else {
            return nil
        }

        guard let contentRect = controller.contentRect(for: model, in: bounds),
              contentRect.contains(point) else {
            return nil
        }

        return super.hitTest(point) ?? self
    }

    private func convertToScreen(_ viewPoint: NSPoint) -> NSPoint {
        guard let window else { return viewPoint }
        let windowPoint = convert(viewPoint, to: nil)
        return window.convertPoint(toScreen: windowPoint)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureTransparency()
    }

    private func configureTransparency() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func layout() {
        super.layout()
        // NSHostingView wraps content in internal NSScrollViews.
        // SwiftUI may recreate them when the view tree changes (e.g.
        // AutoHeightScrollView toggling between scroll/non-scroll mode),
        // so we must re-disable on every layout pass.
        // Guard: only modify properties when they differ to avoid
        // triggering additional layout passes that could loop.
        disableInternalScrollers(in: self)
    }

    private func disableInternalScrollers(in view: NSView) {
        if let scrollView = view as? NSScrollView {
            if scrollView.hasVerticalScroller { scrollView.hasVerticalScroller = false }
            if scrollView.hasHorizontalScroller { scrollView.hasHorizontalScroller = false }
            if scrollView.scrollerStyle != .overlay { scrollView.scrollerStyle = .overlay }
            return
        }
        for child in view.subviews {
            disableInternalScrollers(in: child)
        }
    }
}

// MARK: - NotchEventMonitors

@MainActor
final class NotchEventMonitors {
    private var globalMoveMonitor: Any?
    private var localMoveMonitor: Any?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var globalDragMonitor: Any?
    private var localDragMonitor: Any?
    private var lastMoveTime: TimeInterval = 0

    var isActive: Bool { globalMoveMonitor != nil }

    func start(
        mouseMoveHandler: @MainActor @escaping @Sendable (NSPoint) -> Void,
        mouseDownHandler: @MainActor @escaping @Sendable (NSPoint) -> Void,
        mouseDragHandler: @MainActor @escaping @Sendable (NSPoint) -> Void
    ) {
        let throttleInterval: TimeInterval = 0.05

        nonisolated(unsafe) var sharedLastMove: TimeInterval = 0

        globalMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { event in
            let now = ProcessInfo.processInfo.systemUptime
            guard now - sharedLastMove >= throttleInterval else { return }
            sharedLastMove = now
            let location = NSEvent.mouseLocation
            Task { @MainActor in mouseMoveHandler(location) }
        }

        localMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
            let now = ProcessInfo.processInfo.systemUptime
            guard now - sharedLastMove >= throttleInterval else { return event }
            sharedLastMove = now
            let location = NSEvent.mouseLocation
            Task { @MainActor in mouseMoveHandler(location) }
            return event
        }

        // A pointer with the button held down stops sending `.mouseMoved`
        // entirely, which is why a file dragged towards a closed island never
        // opened it: the shelf was unreachable without opening the panel first.
        nonisolated(unsafe) var sharedLastDrag: TimeInterval = 0

        globalDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { event in
            let now = ProcessInfo.processInfo.systemUptime
            guard now - sharedLastDrag >= throttleInterval else { return }
            sharedLastDrag = now
            let location = NSEvent.mouseLocation
            Task { @MainActor in mouseDragHandler(location) }
        }

        localDragMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { event in
            let now = ProcessInfo.processInfo.systemUptime
            guard now - sharedLastDrag >= throttleInterval else { return event }
            sharedLastDrag = now
            let location = NSEvent.mouseLocation
            Task { @MainActor in mouseDragHandler(location) }
            return event
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { event in
            let location = NSEvent.mouseLocation
            Task { @MainActor in mouseDownHandler(location) }
        }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            let location = NSEvent.mouseLocation
            Task { @MainActor in mouseDownHandler(location) }
            return event
        }
    }

    func stop() {
        if let m = globalMoveMonitor { NSEvent.removeMonitor(m) }
        if let m = localMoveMonitor { NSEvent.removeMonitor(m) }
        if let m = globalClickMonitor { NSEvent.removeMonitor(m) }
        if let m = localClickMonitor { NSEvent.removeMonitor(m) }
        if let m = globalDragMonitor { NSEvent.removeMonitor(m) }
        if let m = localDragMonitor { NSEvent.removeMonitor(m) }
        globalMoveMonitor = nil
        localMoveMonitor = nil
        globalClickMonitor = nil
        localClickMonitor = nil
        globalDragMonitor = nil
        localDragMonitor = nil
    }
}

// MARK: - NSScreen notch size helper

extension NSScreen {
    /// Simulated notch width used on non-notch (external) displays.
    /// Sized close to a real MacBook notch (~200pt) so the closed island
    /// doesn't feel disproportionately wide when the black rectangle is
    /// fully visible (not hidden behind a physical notch).
    static let externalDisplayNotchWidth: CGFloat = 190
    static let externalDisplayNotchHeight: CGFloat = 38

    /// The user's calibration applied on top of what macOS reports.
    var notchSize: CGSize {
        NotchCalibration.current.apply(to: measuredNotchSize)
    }

    /// What macOS says, before any correction.
    var measuredNotchSize: CGSize {
        guard safeAreaInsets.top > 0 else {
            return CGSize(
                width: Self.externalDisplayNotchWidth,
                height: Self.externalDisplayNotchHeight
            )
        }

        let notchHeight = safeAreaInsets.top
        let leftPadding = auxiliaryTopLeftArea?.width ?? 0
        let rightPadding = auxiliaryTopRightArea?.width ?? 0
        let notchWidth = frame.width - leftPadding - rightPadding + 4

        return CGSize(width: notchWidth, height: notchHeight)
    }

    var topStatusBarHeight: CGFloat {
        let reservedTopInset = max(0, frame.maxY - visibleFrame.maxY)
        if reservedTopInset > 0 {
            return reservedTopInset
        }

        if safeAreaInsets.top > 0 {
            return safeAreaInsets.top
        }

        return 24
    }

    var islandClosedHeight: CGFloat {
        NSScreen.computeIslandClosedHeight(
            safeAreaInsetsTop: safeAreaInsets.top,
            topStatusBarHeight: topStatusBarHeight
        )
    }

    /// Pure helper so the height selection logic can be unit-tested without real screen hardware.
    ///
    /// On notch screens, use `safeAreaInsetsTop` directly — the island must match the
    /// physical notch height exactly so it sits flush with the notch bottom edge.
    /// Previously this used `min(safeAreaInsetsTop, topStatusBarHeight)`, but when the
    /// menu bar reserved area is smaller than the notch (e.g. auto-hide menu bar, or
    /// certain display configurations), the island ended up shorter than the physical
    /// notch, leaving a visible gap.
    /// On non-notch screens (`safeAreaInsetsTop == 0`), use `topStatusBarHeight` directly.
    static func computeIslandClosedHeight(
        safeAreaInsetsTop: CGFloat,
        topStatusBarHeight: CGFloat
    ) -> CGFloat {
        if safeAreaInsetsTop > 0 {
            return safeAreaInsetsTop
        }
        return topStatusBarHeight
    }
}
