import AppKit
import Foundation
import SwiftUI

/// Puts the completion banner on screen and takes it away again.
///
/// A window of its own rather than another surface inside the island: it has to
/// outlive the panel opening and closing, and it must not resize the notch.
/// It hangs just below the notch — the middle of the screen is where the work
/// is, and an announcement there gets in the way of the thing it is announcing.
@MainActor
final class CompletionBannerController {
    /// Long enough to read two short lines and reach the close button, short
    /// enough that it is gone before it becomes something to wait out.
    static let visibleDuration: TimeInterval = 4

    /// How far below the notch the banner hangs.
    static let notchGap: CGFloat = 8

    private var panel: NSPanel?
    private var phase = CompletionBannerPhase()
    private let dismissTimer = RepeatingTimerBox()

    func present(
        _ content: CompletionBannerContent,
        on screen: NSScreen?,
        onOpen: ((String) -> Void)? = nil
    ) {
        // A second completion while the first is still showing replaces it.
        // Stacking them under the notch would push the lower one into the work
        // area, which is the thing this position exists to avoid.
        dismiss()

        guard let screen = screen ?? NSScreen.main else { return }
        let panel = makePanel(content: content, on: screen, onOpen: onOpen)
        self.panel = panel
        panel.orderFrontRegardless()
        startDismissCountdown()
    }

    /// Restarts the countdown. Called on arrival, and again when the pointer
    /// leaves — hovering means the user is reading it, and pulling it away
    /// mid-read is the opposite of helpful.
    private func startDismissCountdown() {
        dismissTimer.invalidate()
        // Not `Task.sleep`: the banner must go away even if something cancels
        // the surrounding task, and this timer is owned by a box whose `deinit`
        // stops it.
        let timer = Timer.scheduledTimer(withTimeInterval: Self.visibleDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
        dismissTimer.timer = timer
    }

    func dismiss() {
        dismissTimer.invalidate()
        panel?.orderOut(nil)
        panel = nil
    }

    /// Plays the exit, then takes the window away.
    ///
    /// Used when the banner is opening into the island: the movement up into the
    /// notch is what ties the announcement to the panel that follows it. The
    /// window is ordered out on a timer rather than on an animation callback so
    /// it cannot be left on screen if the animation is interrupted.
    func dismissHandingOff() {
        guard panel != nil else { return }
        dismissTimer.invalidate()
        phase.isLeaving = true
        let timer = Timer.scheduledTimer(
            withTimeInterval: CompletionBannerPhase.exitDuration,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
        dismissTimer.timer = timer
    }

    var isPresenting: Bool { panel != nil }

    private func makePanel(
        content: CompletionBannerContent,
        on screen: NSScreen,
        onOpen: ((String) -> Void)?
    ) -> NSPanel {
        phase = CompletionBannerPhase()
        let view = CompletionBannerView(
            content: content,
            onOpen: onOpen.map { open in { open(content.sessionID) } },
            onClose: { [weak self] in self?.dismiss() },
            onHoverChanged: { [weak self] hovering in
                guard let self else { return }
                if hovering { dismissTimer.invalidate() } else { startDismissCountdown() }
            },
            phase: phase
        )
        let hosting = NSHostingView(rootView: view)
        let size = CompletionBannerView.size
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            // Hanging under the notch, not in the middle of the screen. The
            // middle is where the work is; this belongs next to the island it
            // came out of.
            y: screen.frame.maxY - screen.notchSize.height - Self.notchGap - size.height,
            width: size.width,
            height: size.height
        )

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        // Takes the mouse, unlike every other thing this app puts on screen
        // unbidden — the close button has to be reachable. Safe only because it
        // moved out of the middle of the screen: under the notch it sits over
        // the menu bar strip, where there is nothing to click through to.
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .ignoresCycle, .stationary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        return panel
    }
}

/// Turns a run length into something a person reads at a glance.
///
/// Free of `Date.now` so it can be checked at exact durations.
enum CompletionDurationFormatter {
    static func string(for interval: TimeInterval) -> String? {
        // Under a few seconds there is nothing worth reporting, and "0秒" reads
        // like a failure rather than a fast task.
        guard interval >= 3 else { return nil }

        let total = Int(interval.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 { return "\(hours)時間\(minutes)分" }
        if minutes > 0 { return "\(minutes)分\(seconds)秒" }
        return "\(seconds)秒"
    }
}
