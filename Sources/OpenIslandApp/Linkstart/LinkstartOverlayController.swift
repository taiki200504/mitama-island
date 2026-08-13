import AppKit
import OpenIslandCore
import os
import SwiftUI

/// Puts the login sequence over every screen, and takes it away again.
///
/// Separate from `OverlayPanelController` on purpose: that one owns a small
/// panel that lives for the whole session and must never steal focus. This one
/// owns full-screen windows that exist for six seconds and are meant to be the
/// only thing you can see.
@MainActor
final class LinkstartOverlayController {
    private static let logger = Logger(subsystem: "com.mitama.island", category: "linkstart")

    private var panels: [NSPanel] = []
    private var dismissal: Task<Void, Never>?

    var isPresenting: Bool { !panels.isEmpty }

    /// Shows the sequence. Called again while it is up, it takes it away —
    /// pressing the key twice is the same escape hatch the camera has.
    func toggle() {
        if isPresenting {
            dismiss()
            return
        }
        present()
    }

    func present() {
        dismiss()

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        Self.logger.notice("Presenting across \(screens.count) screen(s)")

        let startedAt = Date()
        let mainScreen = NSScreen.main ?? screens[0]

        panels = screens.map { screen in
            makePanel(
                on: screen,
                startedAt: startedAt,
                // The checklist belongs on the screen being looked at. Repeating
                // it on every display reads as a bug rather than as spectacle.
                showsDetail: screen == mainScreen
            )
        }

        // Key on one panel only: whichever has the key window is where Escape
        // and the closing click arrive.
        panels.first?.makeKeyAndOrderFront(nil)

        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(LinkstartSequence.duration + 1.0))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissal?.cancel()
        dismissal = nil
        guard !panels.isEmpty else { return }
        Self.logger.notice("Dismissing")
        panels.forEach { $0.orderOut(nil) }
        panels = []
    }

    // MARK: - Private

    private func makePanel(on screen: NSScreen, startedAt: Date, showsDetail: Bool) -> NSPanel {
        let panel = LinkstartPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.onDismiss = { [weak self] in self?.dismiss() }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.ignoresMouseEvents = false
        // Above the menu bar and the Dock: this is meant to cover the machine.
        panel.level = .screenSaver
        // `.stationary` for the same reason the island needs it — without it the
        // panel is dragged off screen by the Sonoma wallpaper-reveal gesture.
        panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .ignoresCycle, .stationary]

        let hosting = NSHostingView(
            rootView: LinkstartView(startedAt: startedAt, showsDetail: showsDetail)
        )
        hosting.frame = CGRect(origin: .zero, size: screen.frame.size)
        panel.contentView = hosting
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
        return panel
    }
}

/// A full-screen panel that anyone can get out of.
///
/// Something that covers every display has to be dismissable without knowing a
/// shortcut, so any key and any click take it away — not just Escape.
private final class LinkstartPanel: NSPanel {
    var onDismiss: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        onDismiss?()
    }

    override func mouseDown(with event: NSEvent) {
        onDismiss?()
    }
}
