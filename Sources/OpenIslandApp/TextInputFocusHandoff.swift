import AppKit
import os

/// Borrows application focus for the length of one typed reply, and gives it back.
///
/// The island is a `nonactivatingPanel` on purpose: it must never pull the
/// developer out of the terminal. But macOS binds the input method to the
/// *active application*, not to the key window, so a panel that never activates
/// can receive keystrokes and still have no Japanese input. Typing is the one
/// moment where the trade has to go the other way.
///
/// The borrow is deliberately narrow: it starts when a field begins editing and
/// ends when the island closes, so the app is in front only while there is a
/// caret blinking in it.
@MainActor
enum TextInputFocusHandoff {
    private static let logger = Logger(subsystem: "com.mitama.island", category: "focus")

    private static var borrowedFrom: NSRunningApplication?

    /// Brings the app forward so an input method can attach, remembering who was
    /// in front. Does nothing when the app is already active.
    static func take() {
        guard !NSApp.isActive else { return }

        // Only record the first borrow. A second field taking focus while we are
        // already in front would otherwise remember *us* as the app to return to.
        if borrowedFrom == nil {
            borrowedFrom = NSWorkspace.shared.frontmostApplication
        }
        logger.notice("Taking focus from \(self.borrowedFrom?.localizedName ?? "nothing", privacy: .public)")
        NSApp.activate()
    }

    /// Drops the record without moving the front.
    ///
    /// Called when the app loses focus by some other route — the user switching
    /// away while the island is still open. Without this the record survives
    /// until the island next closes, and the reply after that would send the
    /// front to whichever app was in front two edits ago.
    static func forget() {
        guard borrowedFrom != nil else { return }
        logger.notice("Forgetting the borrow; focus left by another route")
        borrowedFrom = nil
    }

    /// Returns the front to whoever had it. Safe to call when nothing was borrowed.
    static func giveBack() {
        guard let application = borrowedFrom else { return }
        borrowedFrom = nil

        // The app may have quit while the reply was being typed.
        guard !application.isTerminated else { return }
        logger.notice("Returning focus to \(application.localizedName ?? "?", privacy: .public)")
        application.activate()
    }
}
