import AppKit
import OpenIslandCore
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
/// be escapable without knowing a shortcut — except for `dismissGrace` seconds
/// right after it appears, where a keystroke is far more likely to be a reflex
/// to the screen being taken over than a decision to leave. See
/// `OverlayDismissGate`.
final class FullScreenOverlayPanel: NSPanel {
    var onDismiss: (() -> Void)?
    /// 出した時刻と、入力を無視する猶予。0 なら最初の一打で閉じる。
    private var presentedAt = Date()
    private var dismissGrace: TimeInterval = 0

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        dismissIfAllowed()
    }

    override func mouseDown(with event: NSEvent) {
        dismissIfAllowed()
    }

    /// 猶予のあいだの入力は捨てる。**ここで握り潰すだけで、転送はしない**
    /// ——下にあるのは演出そのもので、キーを渡す相手がいない。
    private func dismissIfAllowed() {
        guard OverlayDismissGate.allowsDismiss(
            presentedAt: presentedAt,
            now: Date(),
            grace: dismissGrace
        ) else { return }
        onDismiss?()
    }

    static func make(
        on screen: NSScreen,
        rootView: some View,
        dismissGrace: TimeInterval = 0,
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
        panel.presentedAt = Date()
        panel.dismissGrace = dismissGrace
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
