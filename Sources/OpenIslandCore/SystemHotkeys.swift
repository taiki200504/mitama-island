import Foundation

/// The keyboard shortcuts macOS has reserved for itself.
///
/// Worth knowing because `RegisterEventHotKey` does not: it returns success for
/// a combination the system already owns, and the key then never reaches the
/// app. Nothing fails, nothing logs, and the feature is simply dead. Reading the
/// system's own list is the only way to find out before the user does.
public enum SystemHotkeys {
    public struct Entry: Equatable, Sendable {
        public var keyCode: Int
        public var modifiers: Int
        public var isEnabled: Bool

        public init(keyCode: Int, modifiers: Int, isEnabled: Bool) {
            self.keyCode = keyCode
            self.modifiers = modifiers
            self.isEnabled = isEnabled
        }
    }

    /// The four flags both `NSEvent.ModifierFlags` and the system's list agree
    /// on. Everything else — caps lock, the function key, the device-side bits —
    /// is noise that would make every comparison miss.
    private static let comparableModifiers = 262144 | 131072 | 524288 | 1048576

    public static func entries(from plist: [String: Any]) -> [Entry] {
        plist.values.compactMap { value in
            guard let row = value as? [String: Any],
                  let parameters = (row["value"] as? [String: Any])?["parameters"] as? [Int],
                  parameters.count >= 3 else { return nil }
            return Entry(
                keyCode: parameters[1],
                modifiers: parameters[2],
                // Rows are written with the flag missing when never touched,
                // and those are live defaults rather than disabled ones.
                isEnabled: (row["enabled"] as? Bool) ?? true
            )
        }
    }

    public static func isClaimed(keyCode: Int, modifiers: Int, in entries: [Entry]) -> Bool {
        let wanted = modifiers & comparableModifiers
        return entries.contains {
            $0.isEnabled && $0.keyCode == keyCode && ($0.modifiers & comparableModifiers) == wanted
        }
    }

    /// Reads the live list. Empty when the domain cannot be read, which reads as
    /// "nothing is claimed" — the check is an early warning, not a gate, and it
    /// must never be the reason a shortcut fails to register.
    public static func current(
        defaults: UserDefaults? = UserDefaults(suiteName: "com.apple.symbolichotkeys")
    ) -> [Entry] {
        guard let plist = defaults?.dictionary(forKey: "AppleSymbolicHotKeys") else { return [] }
        return entries(from: plist)
    }
}

/// The key that wakes the camera.
///
/// Was ⌃⇧Space, which macOS reserves (symbolic hotkey 156). Carbon accepted the
/// registration and the system kept the key, so pressing it did nothing at all.
/// ⌃⌥Space is not in the system's default list and is still a one-hand chord —
/// which matters, because the other hand is busy making the gesture.
public enum TouchlessActivationTrigger {
    public static let keyCode = 49
    /// control + option.
    public static let modifiers = 262144 | 524288
    public static let displayLabel = "⌃⌥space"
}
