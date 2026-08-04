import Foundation

/// A value that can round-trip through `UserDefaults`.
///
/// Conformances stay narrow on purpose: preferences are user-facing switches,
/// sliders and pickers, so the representable set is scalars plus string-backed
/// enums. Anything richer belongs in a document, not in defaults.
protocol PreferenceRepresentable {
    static func decodePreference(_ raw: Any) -> Self?
    var preferenceValue: Any { get }
}

extension Bool: PreferenceRepresentable {
    static func decodePreference(_ raw: Any) -> Bool? {
        if let number = raw as? NSNumber { return number.boolValue }
        guard let text = (raw as? String)?.lowercased() else { return nil }
        if ["1", "true", "yes"].contains(text) { return true }
        if ["0", "false", "no"].contains(text) { return false }
        return nil
    }
    var preferenceValue: Any { self }
}

extension Int: PreferenceRepresentable {
    // Strings too: the argument domain and `defaults write -string` both deliver
    // numbers that way, and silently ignoring them looks like the setting is broken.
    static func decodePreference(_ raw: Any) -> Int? {
        (raw as? NSNumber)?.intValue ?? (raw as? String).flatMap(Int.init)
    }
    var preferenceValue: Any { self }
}

extension Double: PreferenceRepresentable {
    static func decodePreference(_ raw: Any) -> Double? {
        (raw as? NSNumber)?.doubleValue ?? (raw as? String).flatMap(Double.init)
    }
    var preferenceValue: Any { self }
}

extension String: PreferenceRepresentable {
    static func decodePreference(_ raw: Any) -> String? { raw as? String }
    var preferenceValue: Any { self }
}

extension Array: PreferenceRepresentable where Element == String {
    static func decodePreference(_ raw: Any) -> [String]? { raw as? [String] }
    var preferenceValue: Any { self }
}

/// String-backed enums get their conformance for free.
extension PreferenceRepresentable where Self: RawRepresentable, Self.RawValue == String {
    static func decodePreference(_ raw: Any) -> Self? {
        (raw as? String).flatMap(Self.init(rawValue:))
    }
    var preferenceValue: Any { rawValue }
}

/// Thin typed wrapper over a `UserDefaults` suite.
///
/// Deliberately has no cache: `UserDefaults` already keeps values in memory, and
/// reading straight through keeps defaults the single source of truth. That
/// matters while `AppModel` still writes some of the same keys.
final class PreferenceStore: @unchecked Sendable {
    static let standard = PreferenceStore(suite: .standard)

    private let suite: UserDefaults

    init(suite: UserDefaults) {
        self.suite = suite
    }

    func value<T: PreferenceRepresentable>(_ key: String, default fallback: T) -> T {
        guard let raw = suite.object(forKey: key), let decoded = T.decodePreference(raw) else {
            return fallback
        }
        return decoded
    }

    func setValue<T: PreferenceRepresentable>(_ value: T, forKey key: String) {
        suite.set(value.preferenceValue, forKey: key)
    }

    func hasValue(forKey key: String) -> Bool {
        suite.object(forKey: key) != nil
    }

    func removeValue(forKey key: String) {
        suite.removeObject(forKey: key)
    }
}
