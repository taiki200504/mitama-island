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
    static func decodePreference(_ raw: Any) -> Bool? { (raw as? NSNumber)?.boolValue }
    var preferenceValue: Any { self }
}

extension Int: PreferenceRepresentable {
    static func decodePreference(_ raw: Any) -> Int? { (raw as? NSNumber)?.intValue }
    var preferenceValue: Any { self }
}

extension Double: PreferenceRepresentable {
    static func decodePreference(_ raw: Any) -> Double? { (raw as? NSNumber)?.doubleValue }
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
