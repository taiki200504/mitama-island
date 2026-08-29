import AppKit
import SwiftUI

/// A panel that covers one whole screen and gets out of the way on any input.
///
/// Shared by the login sequence and the idle board because the configuration
/// carries two traps that are expensive to rediscover:
///
/// - `.screenSaver` level, so it sits above the menu bar and the Dock. Anything
///   lower is not covering the machine, it is a large window.
/// - `.stationary` in the collection behaviour. Without it the Sonoma
///   wallpaper-reveal gesture drags the panel off screen — the island's own
///   panel had already been bitten by this.
///
/// Any key and any click dismiss it. Something that owns every display has to
/// be escapable without knowing a shortcut.
final class FullScreenOverlayPanel: NSPanel {
    var onDismiss: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        onDismiss?()
    }

    override func mouseDown(with event: NSEvent) {
        onDismiss?()
    }

    static func make(
        on screen: NSScreen,
        rootView: some View,
        onDismiss: @escaping () -> Void
    ) -> FullScreenOverlayPanel {
        let panel = FullScreenOverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.onDismiss = onDismiss
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.ignoresMouseEvents = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .ignoresCycle, .stationary]

        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = CGRect(origin: .zero, size: screen.frame.size)
        panel.contentView = hosting
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
        return panel
    }
}
