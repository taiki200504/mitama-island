import AppKit

extension NSWindow {
    /// Takes the window away for good, instead of only off the screen.
    ///
    /// `orderOut` pulls a window off the screen but leaves it in the
    /// application's window list, so AppKit keeps holding it — and with it the
    /// `NSHostingView` inside and the whole SwiftUI graph that view is driving.
    /// A graph with a `TimelineView(.animation)` in it goes on asking for a
    /// frame at the display's refresh rate **where nobody can see it**, for the
    /// rest of the launch. That is what the login sequence and the completion
    /// burst were each leaving behind.
    ///
    /// Dropping `contentView` is what actually cuts the graph loose; `close`
    /// is what gets the window out of the list. Every caller must have set
    /// `isReleasedWhenClosed = false`, or `close` and ARC both try to free it.
    func tearDownHostedContent() {
        orderOut(nil)
        contentView = nil
        close()
    }
}
