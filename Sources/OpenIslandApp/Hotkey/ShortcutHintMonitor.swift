import AppKit
import Foundation
import Observation

/// Publishes whether the shortcut modifier is being held right now.
///
/// Holding ⌃ is what reveals which letter each button answers to. Unlike the
/// shortcuts themselves, watching modifier keys **does** need Accessibility
/// permission — the app already holds it for returning to a terminal. Without
/// it the hints simply never appear; nothing else stops working, and the
/// settings pane says which is the case rather than leaving it a mystery.
@MainActor
@Observable
final class ShortcutHintMonitor {
    private(set) var isModifierHeld = false
    /// Fires when the modifier comes up, which is what ends a hold-to-cycle.
    var onModifierReleased: (() -> Void)?
    private(set) var hasAccessibilityPermission = AXIsProcessTrusted()

    private var monitor: Any?
    private var localMonitor: Any?
    private var modifier: ShortcutModifier = .control

    func start(modifier: ShortcutModifier) {
        self.modifier = modifier
        stop()
        hasAccessibilityPermission = AXIsProcessTrusted()
        guard hasAccessibilityPermission else { return }

        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated { self?.update(with: event) }
        }
        // The global monitor does not see events delivered to our own windows,
        // so the settings window needs the local one to behave the same way.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated { self?.update(with: event) }
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        monitor = nil
        localMonitor = nil
        isModifierHeld = false
    }

    private func update(with event: NSEvent) {
        let held = event.modifierFlags.contains(modifier.flags)
        let wasHeld = isModifierHeld
        isModifierHeld = held
        if wasHeld, !held { onModifierReleased?() }
    }
}
