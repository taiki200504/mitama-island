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
        // Only loaded back when persistence is on — otherwise turning it off
        // would still leave a previous session's history readable until it
        // happened to be overwritten.
        if settings.clipboard.persistsToDisk {
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
    func applyClipboardEnabled(_ enabled: Bool) {
        if enabled {
            pasteboardWatcher.start()
        } else {
            pasteboardWatcher.stop()
        }
        panelHotkeys?.clipboardOpenEnabled = enabled
        panelHotkeys?.startPersistentBindings()
    }

    /// A row's default action: copy it back (or paste it back, per the
    /// setting), then close the island the way picking a session or an
    /// answer already does.
    func selectClipboardItem(_ item: ClipboardItem) {
        clipboard.pasteBack(item)
        notchClose()
    }
}
