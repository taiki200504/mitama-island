import SwiftUI
import OpenIslandCore

// Slightly longer than the close animation so the collapse is never cut off
// mid-shrink by the surface being torn down.
private let openedSurfaceUnmountDelay: TimeInterval = 0.22

/// Measures `openedContent`'s actual rendered height (below the notch header
/// row, and already capped to whatever room the window has — see
/// `openedSurface`). `OverlayPanelController` uses this for hit-testing, so
/// the clickable area follows what's really on screen instead of only the
/// height estimate. Mirrors the `ContentHeightKey`/`NotificationContentHeightKey`
/// pattern already used for `AppModel.measuredNotificationContentHeight`.
private struct OpenedSurfaceHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Main island view

struct IslandPanelView: View {
    /// True while a file drag is hovering the island, so the shelf can come out
    /// to meet it.
    @State var isShelfTargeted = false
    /// True while the pointer rests on the shelf badge, which is the only time
    /// what is on the shelf is worth the room it takes.
    @State var isShelfBadgeHovered = false
    /// True while a file is held over the closed pill.
    @State private var isClosedPillTargeted = false
    static let headerControlButtonSize: CGFloat = 22
    static let headerControlSpacing: CGFloat = 8
    static let headerHorizontalPadding: CGFloat = 18
    static let headerTopPadding: CGFloat = 2
    static let notchHeaderHorizontalPadding: CGFloat = 46
    static let notchLaneSafetyInset: CGFloat = 12
    static let minimumRightUsageLaneWidth: CGFloat = 58

    var model: AppModel
    var lang: LanguageManager { model.lang }

    @State private var isHovering = false
    @State var showingQuitConfirmation = false
    @State private var keepsOpenedSurfaceMounted = false
    @State private var openedSurfaceMountGeneration: UInt64 = 0

    private var isOpened: Bool {
        model.notchStatus == .opened
    }

    private var usesOpenedVisualState: Bool {
        isOpened
    }

    private var shouldRenderOpenedSurface: Bool {
        usesOpenedVisualState || keepsOpenedSurfaceMounted
    }

    private var isPopping: Bool {
        model.notchStatus == .popping
    }

    /// Single animation selection based on the current notch status.
    private var notchTransitionAnimation: Animation {
        switch model.notchStatus {
        case .opened:  return IslandThemes.current.animationProfile.open
        case .closed:  return IslandThemes.current.animationProfile.close
        case .popping: return IslandThemes.current.animationProfile.pop
        }
    }

    var targetOverlayScreen: NSScreen? {
        if let targetScreenID = model.overlayPlacementDiagnostics?.targetScreenID,
           let screen = NSScreen.screens.first(where: { OverlayDisplayResolver.screenID(for: $0) == targetScreenID }) {
            return screen
        }

        return NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    var usesNotchAwareOpenedHeader: Bool {
        model.overlayPlacementDiagnostics?.mode == .notch
            || targetOverlayScreen?.safeAreaInsets.top ?? 0 > 0
    }

    /// True when the closed island sits on an external (non-notched) display.
    /// The central black rectangle is otherwise aligned with the physical
    /// notch, so center content is only useful here.
    private var isExternalDisplayPlacement: Bool {
        if let mode = model.overlayPlacementDiagnostics?.mode {
            return mode == .topBar
        }
        // Fallback when diagnostics haven't been populated yet.
        return (targetOverlayScreen?.safeAreaInsets.top ?? 0) == 0
    }

    /// True while the camera is open and watching for a hand.
    var cameraIsWatching: Bool {
        model.cameraActivation.phase == .awaitingGesture
    }

    var openedHeaderButtonsWidth: CGFloat {
        // The watching mark occupies a control slot, so the lane has to reserve
        // room for it. A fixed count here compresses the usage lane's neighbour
        // instead of widening the lane.
        let controls = cameraIsWatching ? 4 : 3
        return (Self.headerControlButtonSize * CGFloat(controls))
            + (Self.headerControlSpacing * CGFloat(controls - 1))
    }

    var openedHeaderHorizontalPadding: CGFloat {
        usesNotchAwareOpenedHeader ? Self.notchHeaderHorizontalPadding : Self.headerHorizontalPadding
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color.clear

                notchContent(availableSize: geometry.size)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .alert(model.lang.t("island.quit.confirmTitle"), isPresented: $showingQuitConfirmation) {
            Button(model.lang.t("island.quit.confirmAction"), role: .destructive) {
                model.quitApplication()
            }
            Button(model.lang.t("settings.general.cancel"), role: .cancel) {}
        } message: {
            Text(model.lang.t("island.quit.confirmMessage"))
        }
        .onAppear {
            syncOpenedSurfaceMount(with: model.notchStatus, immediate: true)
        }
        .onChange(of: model.notchStatus) { _, status in
            syncOpenedSurfaceMount(with: status)
        }
    }

    @ViewBuilder
    private func notchContent(availableSize: CGSize) -> some View {
        // Window is always at opened size — use opened insets unconditionally.
        let panelShadowHorizontalInset = IslandChromeMetrics.openedShadowHorizontalInset
        let panelShadowBottomInset = IslandChromeMetrics.openedShadowBottomInset
        let layoutWidth = max(0, availableSize.width - (panelShadowHorizontalInset * 2))
        let layoutHeight = max(0, availableSize.height - panelShadowBottomInset)

        let outerHorizontalPadding: CGFloat = 0
        let outerBottomPadding: CGFloat = 0
        let openedWidth = max(0, layoutWidth - outerHorizontalPadding)
        let openedHeight = max(closedNotchHeight, layoutHeight - outerBottomPadding)

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                if shouldRenderOpenedSurface {
                    openedSurface(width: openedWidth, height: openedHeight)
                        .opacity(usesOpenedVisualState ? 1 : 0)
                        .allowsHitTesting(usesOpenedVisualState)
                }

                v6ClosedSurface()
                    .opacity(usesOpenedVisualState ? 0 : 1)
                    .allowsHitTesting(!usesOpenedVisualState)
                    // The pill sits against the physical notch, so it cannot
                    // grow a border to answer the cursor — a glow is the only
                    // edge it has room for. A file held over it gets the same
                    // glow, turned up: that glow is the whole answer to "can I
                    // let go here".
                    .shadow(
                        color: closedPillGlow,
                        radius: IslandThemes.current.glowRadius * (isClosedPillTargeted ? 4 : 3)
                    )
                    // Dropping on the closed island, without opening it first.
                    // The wait and the movement in between were the reason
                    // putting a file down felt far away.
                    .dropDestination(for: URL.self) { urls, _ in
                        guard model.putOnShelf(urls) else { return false }
                        model.notchPop()
                        return true
                    } isTargeted: { isClosedPillTargeted = $0 }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scaleEffect(closedSurfaceScale, anchor: .top)
        .padding(.horizontal, panelShadowHorizontalInset)
        .padding(.bottom, panelShadowBottomInset)
        .animation(notchTransitionAnimation, value: model.notchStatus)
        .animation(IslandThemes.current.animationProfile.pop, value: isClosedPillTargeted)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            if model.notchStatus != .opened {
                model.notchOpen(reason: .click)
            }
        }
    }

    /// The pill answers a held file the same way it answers the cursor, only
    /// more so.
    private var closedPillGlow: Color {
        guard !usesOpenedVisualState else { return .clear }
        let accent = IslandThemes.current.accent
        if isClosedPillTargeted { return accent.opacity(0.9) }
        return isHovering ? accent.opacity(0.55) : .clear
    }

    private var closedSurfaceScale: CGFloat {
        guard !usesOpenedVisualState else { return 1 }
        if isClosedPillTargeted { return IslandChromeMetrics.closedHoverScale * 1.06 }
        return isHovering ? IslandChromeMetrics.closedHoverScale : 1
    }

    private func syncOpenedSurfaceMount(with status: NotchStatus, immediate: Bool = false) {
        openedSurfaceMountGeneration &+= 1
        let generation = openedSurfaceMountGeneration

        switch status {
        case .opened:
            keepsOpenedSurfaceMounted = true
        case .closed, .popping:
            guard !immediate else {
                keepsOpenedSurfaceMounted = false
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + openedSurfaceUnmountDelay) {
                guard openedSurfaceMountGeneration == generation,
                      model.notchStatus != .opened else {
                    return
                }
                keepsOpenedSurfaceMounted = false
            }
        }
    }

    // MARK: - v6 closed surface

    /// Closed island per v6 spec. Renders the flat-top pill with the
    /// UnifiedBars glyph, respecting the user's right-slot / center-label
    /// preferences. AppModel is @Observable so any change to sessions /
    /// preferences re-renders this automatically; UnifiedBars runs its own
    /// TimelineView internally for bar animation.
    @ViewBuilder
    private func v6ClosedSurface() -> some View {
        let layout: V6ClosedLayout = isExternalDisplayPlacement ? .external : .macbook
        let physicalNotchWidth: CGFloat = targetOverlayScreen?.notchSize.width ?? 180
        // One tick a minute, which is the resolution the band shows. The pill
        // has no other reason to redraw on a timer, and a waiting request is
        // exactly the situation where nothing else is arriving to redraw it.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            V6ClosedPill(
                mode: model.islandClosedMode,
                label: layout == .external ? model.islandClosedLabel() : nil,
                rightSlot: model.islandClosedRightSlotContent(),
                peek: model.islandPeekBand(now: context.date),
                layout: layout,
                height: closedNotchHeight,
                physicalNotchWidth: layout == .macbook ? physicalNotchWidth : 0,
                minWidth: 70
            )
        }
        .scaleEffect(isPopping ? 1.04 : 1, anchor: .top)
        .animation(IslandThemes.current.animationProfile.pop, value: isPopping)
    }

    // MARK: - Opened surface

    @ViewBuilder
    private func openedSurface(width openedWidth: CGFloat, height openedHeight: CGFloat) -> some View {
        let horizontalInset = 0.0
        let bottomInset = 0.0
        let surfaceWidth = openedWidth + (horizontalInset * 2)
        let surfaceHeight = openedHeight + bottomInset
        let surfaceShape = OpenedIslandSurfaceShape(
            topProfile: usesNotchAwareOpenedHeader ? .notch : .topBar
        )
        // The SAO theme's double-border look. No longer read from a theme
        // value now that there is only one theme to draw.
        let borderWidth: CGFloat = 1
        let borderOpacity = 0.22
        let scanlineIntensity = IslandThemes.current.scanlineIntensity

        ZStack(alignment: .top) {
            surfaceShape
                .fill(V6Palette.ink)
                .frame(width: surfaceWidth, height: surfaceHeight)

            VStack(spacing: 0) {
                openedHeaderContent
                    .frame(height: closedNotchHeight)

                openedContent
                    .frame(width: openedWidth)
                    .frame(maxHeight: max(0, openedHeight - closedNotchHeight), alignment: .top)
                    .clipped()
                    // Measures the space this content actually occupies —
                    // already capped by the `.frame(maxHeight:)` above, so
                    // this reports at most what's really visible, never more.
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: OpenedSurfaceHeightKey.self,
                                value: geometry.size.height
                            )
                        }
                    )
            }
            .frame(width: openedWidth, height: openedHeight, alignment: .top)
            .padding(.horizontal, horizontalInset)
            .padding(.bottom, bottomInset)
            .clipShape(surfaceShape)
            .onPreferenceChange(OpenedSurfaceHeightKey.self) { height in
                // Same 2pt tolerance as `measuredNotificationContentHeight`,
                // applied here instead of in a `didSet` — this property has
                // no side effects, so the tolerance has to live at the
                // write site.
                guard height > 0, abs(height - model.openedSurfaceMeasuredHeight) >= 2 else { return }
                model.openedSurfaceMeasuredHeight = height
            }
            .overlay {
                ZStack {
                    surfaceShape
                        .stroke(V6Palette.paper.opacity(borderOpacity), lineWidth: borderWidth)
                    // Scaled rather than padded. `OpenedIslandSurfaceShape` is
                    // not insettable, and laying it out in a smaller rect
                    // redraws the notch cut-out at the new size — the second
                    // line then crosses the first near the top instead of
                    // running parallel to it. Scaling is not a true parallel
                    // offset either, but it keeps the profile's proportions.
                    surfaceShape
                        .stroke(V6Palette.paper.opacity(borderOpacity * 0.6), lineWidth: borderWidth)
                        .scaleEffect(
                            x: (surfaceWidth - 4) / surfaceWidth,
                            y: (surfaceHeight - 4) / surfaceHeight
                        )
                }
            }

            if scanlineIntensity > 0 {
                // Rebuilt on every frame of the open and close springs, and only
                // then — the panel holds its size while it is open, so this is a
                // third of a second of path building, not a standing cost.
                Canvas { context, size in
                    var scanlines = Path()
                    for y in stride(from: 0, through: size.height, by: 3) {
                        scanlines.move(to: CGPoint(x: 0, y: y))
                        scanlines.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(scanlines, with: .color(V6Palette.paper.opacity(scanlineIntensity)), lineWidth: 1)
                }
                .frame(width: openedWidth, height: openedHeight)
                .padding(.horizontal, horizontalInset)
                .padding(.bottom, bottomInset)
                .clipShape(surfaceShape)
                .allowsHitTesting(false)
            }
        }
        .frame(width: surfaceWidth, height: surfaceHeight, alignment: .top)
    }

    // MARK: - Closed state

    private var closedNotchWidth: CGFloat {
        (targetOverlayScreen ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }))?.notchSize.width ?? NSScreen.externalDisplayNotchWidth
    }

    private var closedNotchHeight: CGFloat {
        (targetOverlayScreen ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }))?.islandClosedHeight ?? 24
    }
}
