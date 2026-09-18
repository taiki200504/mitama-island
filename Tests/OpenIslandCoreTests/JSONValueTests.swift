import Foundation
import Testing
@testable import OpenIslandCore

@Suite("JSONValue conversion from JSONSerialization output")
struct JSONValueTests {
    /// Round-trips through real `JSONSerialization` output rather than
    /// building `NSNumber`/`NSNull` by hand — the boolean/number distinction
    /// this type exists to get right only shows up in what
    /// `JSONSerialization` itself actually produces.
    private func decode(_ json: String) -> [String: Any] {
        let data = Data(json.utf8)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    @Test("A JSON boolean becomes .bool, not .number")
    func booleanIsBool() {
        let object = decode(#"{"playing": true}"#)
        let value = JSONValue(jsonObject: object["playing"]!)
        #expect(value == .bool(true))
    }

    @Test("A JSON number becomes .number")
    func numberIsNumber() {
        let object = decode(#"{"elapsedTime": 12.5}"#)
        let value = JSONValue(jsonObject: object["elapsedTime"]!)
        #expect(value == .number(12.5))
    }

    @Test("A JSON string becomes .string")
    func stringIsString() {
        let object = decode(#"{"title": "Song"}"#)
        let value = JSONValue(jsonObject: object["title"]!)
        #expect(value == .string("Song"))
    }

    @Test("A JSON null becomes .null")
    func nullIsNull() {
        let object = decode(#"{"artist": null}"#)
        let value = JSONValue(jsonObject: object["artist"]!)
        #expect(value == .null)
        #expect(value?.isNull == true)
    }

    @Test("A nested object converts every key")
    func nestedObject() {
        let object = decode(#"{"outer": {"a": 1, "b": "two"}}"#)
        let value = JSONValue(jsonObject: object["outer"]!)
        #expect(value == .object(["a": .number(1), "b": .string("two")]))
    }

    @Test("An array converts every element in order")
    func arrayPreservesOrder() {
        let object = decode(#"{"list": [1, "two", false]}"#)
        let value = JSONValue(jsonObject: object["list"]!)
        #expect(value == .array([.number(1), .string("two"), .bool(false)]))
    }

    @Test("A full top-level object decodes into .object")
    func topLevelObject() {
        let object = decode(#"{"title": "Song", "playing": true, "elapsedTime": 5}"#)
        let value = JSONValue(jsonObject: object)
        #expect(value == .object([
            "title": .string("Song"),
            "playing": .bool(true),
            "elapsedTime": .number(5),
        ]))
    }
}
