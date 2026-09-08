import Foundation

/// A `Sendable` JSON value.
///
/// `JSONSerialization` decodes to `[String: Any]`, and `Any` can box
/// arbitrary reference types — the compiler has no way to know the boxed
/// value is actually just immutable JSON data, so `[String: Any]` itself is
/// never `Sendable`. Converting once, right after parsing, into this type is
/// what lets a parsed payload cross an actor boundary (e.g. into
/// `NowPlayingCoordinator`, `@MainActor`) without an `@unchecked Sendable`
/// escape hatch.
public enum JSONValue: Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    /// Converts one value out of `JSONSerialization`'s own output
    /// (`NSString`, `NSNumber` — including the boxed booleans it uses for
    /// JSON `true`/`false` — `NSNull`, `[Any]`, `[String: Any]`) into
    /// `JSONValue`. `nil` for anything else, which shouldn't occur since
    /// this is only ever run on `JSONSerialization`'s own output.
    public init?(jsonObject: Any) {
        switch jsonObject {
        case is NSNull:
            self = .null
        case let string as String:
            self = .string(string)
        case let number as NSNumber:
            // JSONSerialization represents both numbers and booleans as
            // NSNumber; CFGetTypeID is the standard way to tell them apart.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case let array as [Any]:
            self = .array(array.compactMap(JSONValue.init(jsonObject:)))
        case let object as [String: Any]:
            var converted: [String: JSONValue] = [:]
            for (key, value) in object {
                converted[key] = JSONValue(jsonObject: value)
            }
            self = .object(converted)
        default:
            return nil
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var doubleValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}
