import AppKit
import Foundation
import Observation
import OpenIslandCore
import os
import SwiftUI

/// Puts the idle board over every screen once the machine has been left alone,
/// and takes it away the moment anything is touched.
///
/// Deliberately not a `.saver` bundle. A screen saver is a separate process
/// with no access to the sessions, the mitama feed or the calendar this is
/// entirely about, and it would have to be installed separately. The panel the
/// login sequence already uses covers the machine just as completely.
@MainActor
@Observable
final class AmbientOverlayController {
    private static let logger = Logger(subsystem: "com.mitama.island", category: "ambient")

    @ObservationIgnored private var panels: [NSPanel] = []
    @ObservationIgnored private var returnFocusTo: NSRunningApplication?

    /// Set by `AppModel`. Everything the board needs, asked for at the moment
    /// it is drawn rather than pushed in — the board can stay up for hours and
    /// a snapshot taken at presentation time would go stale on screen.
    @ObservationIgnored var board: () -> AmbientBoard = { .make(for: []) }
    @ObservationIgnored var nextEvent: () -> UpcomingCalendarEvent.Band? = { nil }
    @ObservationIgnored var lang: LanguageManager = .shared
    /// Called when the board goes away, so the idle count restarts from zero
    /// instead of re-presenting on the next tick.
    @ObservationIgnored var onDismiss: (() -> Void)?

    var isPresenting: Bool { !panels.isEmpty }

    func present() {
        guard !isPresenting else { return }

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        Self.logger.notice("Presenting across \(screens.count) screen(s)")

        panels = screens.map { screen in
            FullScreenOverlayPanel.make(
                on: screen,
                rootView: AmbientBoardView(
                    board: board(),
                    nextEvent: nextEvent(),
                    lang: lang
                ),
                onDismiss: { [weak self] in self?.dismiss() }
            )
        }
        panels.first?.makeKeyAndOrderFront(nil)

        // A key window in a background app receives no keystrokes, and this
        // covers every display: without coming forward, the only way out would
        // be the mouse. The front is handed back on the way out.
        if !NSApp.isActive {
            returnFocusTo = NSWorkspace.shared.frontmostApplication
            NSApp.activate()
        }
    }

    func dismiss() {
        guard !panels.isEmpty else { return }
        Self.logger.notice("Dismissing")
        panels.forEach { $0.orderOut(nil) }
        panels = []

        if let returnFocusTo, !returnFocusTo.isTerminated {
            returnFocusTo.activate()
        }
        returnFocusTo = nil
        onDismiss?()
    }
}
