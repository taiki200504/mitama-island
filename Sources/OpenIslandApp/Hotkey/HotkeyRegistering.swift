import AppKit
import Foundation

/// When a shortcut is allowed to fire.
///
/// Single letters like ⌃Y are only safe while the panel is open. Registered
/// permanently they would swallow the same keystroke inside an editor, and a
/// status bar app that eats your typing is worse than one with no shortcuts.
enum HotkeyScope: Hashable, Sendable {
    /// Always live. Reserved for combinations chosen to be unlikely.
    case persistent
    /// Only while the island's panel is expanded.
    case panelExpanded
    /// Only while the session switcher is on screen.
    case switcherActive
}

/// One registered shortcut.
struct HotkeyBinding: Hashable, Sendable {
    let id: String
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags
    let scope: HotkeyScope

    // `NSEvent.ModifierFlags` is not Hashable-by-default in a useful way here.
    static func == (lhs: HotkeyBinding, rhs: HotkeyBinding) -> Bool {
        lhs.id == rhs.id && lhs.keyCode == rhs.keyCode
            && lhs.modifiers == rhs.modifiers && lhs.scope == rhs.scope
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(keyCode)
        hasher.combine(modifiers.rawValue)
        hasher.combine(scope)
    }
}

/// The seam between "which shortcuts should exist" and "talk to Carbon".
///
/// Tests drive a recording double, so the decision logic can be exercised
/// without registering anything system-wide.
@MainActor
protocol HotkeyRegistering: AnyObject {
    /// Replaces every binding in `scope` with `bindings`.
    ///
    /// Replace rather than add: the alternative is remembering what was
    /// registered last time, and a missed unregister leaves a shortcut alive
    /// after the panel closes.
    func setBindings(_ bindings: [HotkeyBinding], for scope: HotkeyScope)
    func removeBindings(for scope: HotkeyScope)
    /// Called on the main actor when a registered shortcut fires.
    var onFire: ((String) -> Void)? { get set }
}
