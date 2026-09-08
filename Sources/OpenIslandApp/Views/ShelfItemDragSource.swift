import AppKit
import SwiftUI

/// Hands a shelved file to the rest of the machine as a **move**.
///
/// SwiftUI's `draggable` only ever offers a copy, and a copy is the wrong
/// promise here. What sits on the shelf is already a duplicate of something;
/// taking it off means it is not on the shelf any more. So the drag says
/// `.move`, the receiver does the moving, and the row leaves with the file.
///
/// The right-click menu comes along for the ride: this view sits over the chip
/// and takes its mouse events, so a menu left behind in SwiftUI would never be
/// reached.
struct ShelfItemDragSource: NSViewRepresentable {
    let url: URL
    /// Called once the file has gone somewhere. The shelf drops the row — and
    /// deletes the copy if the receiver took one rather than moving it.
    let onTakenAway: () -> Void
    /// ⌥-click removes the item without a drag — the same result as taking it
    /// off the shelf, reached without leaving the pointer over the chip.
    let onOptionClick: () -> Void
    let menuEntries: [MenuEntry]

    struct MenuEntry {
        let title: String
        /// Takes the view the menu was raised over — the share sheet needs a
        /// real `NSView` to anchor its popover to, and the other entries just
        /// ignore it.
        let action: (NSView) -> Void
    }

    func makeNSView(context: Context) -> ShelfDragSourceView {
        let view = ShelfDragSourceView()
        configure(view)
        return view
    }

    func updateNSView(_ view: ShelfDragSourceView, context: Context) {
        configure(view)
    }

    private func configure(_ view: ShelfDragSourceView) {
        view.url = url
        view.onTakenAway = onTakenAway
        view.onOptionClick = onOptionClick
        view.menuEntries = menuEntries
    }
}

/// The AppKit half. Starts the drag, reports where it ended, and carries the
/// context menu.
final class ShelfDragSourceView: NSView, NSDraggingSource {
    var url: URL?
    var onTakenAway: (() -> Void)?
    var onOptionClick: (() -> Void)?
    var menuEntries: [ShelfItemDragSource.MenuEntry] = []

    /// The island's panel never becomes the active application, so without this
    /// the first press would be spent waking it up instead of starting a drag.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// ⌥-click removes the item on the spot; anything else waits for
    /// `mouseDragged` to decide whether a drag is starting.
    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.option) else { return }
        onOptionClick?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let url else { return }

        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(bounds, contents: NSWorkspace.shared.icon(forFile: url.path))
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        // There is nowhere inside the island to put it — dropping it back on
        // the shelf it came from is not a move worth making.
        context == .outsideApplication ? .move : []
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        // An empty operation is a drag let go over nothing. The file stays.
        guard operation != [] else { return }
        onTakenAway?()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard !menuEntries.isEmpty else { return nil }

        let menu = NSMenu()
        for (index, entry) in menuEntries.enumerated() {
            let item = NSMenuItem(
                title: entry.title,
                action: #selector(runMenuEntry(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            menu.addItem(item)
        }
        return menu
    }

    @objc private func runMenuEntry(_ sender: NSMenuItem) {
        guard menuEntries.indices.contains(sender.tag) else { return }
        menuEntries[sender.tag].action(self)
    }
}
