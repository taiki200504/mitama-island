import Foundation
import OpenIslandCore

/// Wires `ClipboardStore` and `PasteboardWatcher` into the rest of the app:
/// the watcher only runs while the setting is on and the screen isn't
/// locked, and every setting it reads is read fresh rather than cached, so a
/// toggle flipped mid-session takes effect immediately.
extension AppModel {
    func configureClipboard() {
        clipboard.watcher = pasteboardWatcher
        clipboard.persistsToDisk = { [weak self] in self?.settings.clipboard.persistsToDisk ?? false }
        clipboard.pastesOnSelectEnabled = { [weak self] in self?.settings.clipboard.pastesOnSelect ?? false }
        // Only loaded back when the feature and persistence are both on —
        // `applyClipboardEnabled(false)` below purges everything anyway when
        // the feature itself is off, so loading first would just be read
        // straight back out.
        if settings.clipboard.enabled, settings.clipboard.persistsToDisk {
            clipboard.load()
        }

        pasteboardWatcher.onNewItem = { [weak self] item in
            self?.clipboard.record(item)
        }

        applyClipboardEnabled(settings.clipboard.enabled)
    }

    /// Starts or stops the watcher as the setting changes — the settings pane
    /// calls this from the toggle's own `set`, the same way
    /// `TimerSettings.eyeBreakEnabled`'s row starts and resets the timer
    /// directly rather than polling the setting on a timer of its own.
    ///
    /// Turning the feature off also purges the store, in memory and on disk:
    /// "off" has to mean nothing is left to read, not merely that nothing new
    /// is being added — otherwise turning it back on would resurrect
    /// whatever was recorded before the person switched it off.
    func applyClipboardEnabled(_ enabled: Bool) {
        if enabled {
            pasteboardWatcher.start()
        } else {
            pasteboardWatcher.stop()
            clipboard.purge()
        }
        panelHotkeys?.clipboardOpenEnabled = enabled
        panelHotkeys?.startPersistentBindings()
    }

    /// A row's default action: copy it back, close the island, and — only
    /// when paste-on-select is on and Accessibility is actually granted —
    /// send a ⌘V once the island is out of the way.
    ///
    /// The copy happens first so the pasteboard is right even if nothing
    /// else follows. The ⌘V is deliberately posted a tick after
    /// `notchClose()` rather than before it: posting it immediately can land
    /// while the island (or its own search field) still has focus, pasting
    /// into the wrong place instead of into whatever app the user actually
    /// meant.
    func selectClipboardItem(_ item: ClipboardItem) {
        clipboard.copy(item)
        let shouldPaste = clipboard.shouldPostPasteKeystroke
        notchClose()
        guard shouldPaste else { return }
        Task { @MainActor in
            await Task.yield()
            clipboard.postPasteKeystroke()
        }
    }
}
