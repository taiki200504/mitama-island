import Foundation
import Testing
@testable import OpenIslandCore

/// `RegisterEventHotKey` returns success for a combination macOS has already
/// reserved, and the key then never arrives. The app registered ⌃⇧Space, was
/// told it worked, and silently did nothing for every press — this is the check
/// that was missing.
struct SystemHotkeyTests {
    private let control = 262144
    private let shift = 131072
    private let option = 524288

    /// The shape `defaults read com.apple.symbolichotkeys` actually returns.
    private func plist(_ rows: [(id: String, keyCode: Int, modifiers: Int, enabled: Bool)]) -> [String: Any] {
        var out: [String: Any] = [:]
        for row in rows {
            out[row.id] = [
                "enabled": row.enabled,
                "value": ["parameters": [65535, row.keyCode, row.modifiers], "type": "standard"],
            ]
        }
        return out
    }

    @Test("A combination macOS has reserved is reported as taken")
    func detectsAClaimedCombination() {
        let entries = SystemHotkeys.entries(from: plist([
            (id: "156", keyCode: 49, modifiers: 262144 + 131072, enabled: true)
        ]))
        #expect(SystemHotkeys.isClaimed(keyCode: 49, modifiers: control | shift, in: entries))
    }

    /// A shortcut the user switched off in System Settings is fair game.
    @Test("A disabled system shortcut does not count")
    func ignoresDisabledEntries() {
        let entries = SystemHotkeys.entries(from: plist([
            (id: "156", keyCode: 49, modifiers: 262144 + 131072, enabled: false)
        ]))
        #expect(SystemHotkeys.isClaimed(keyCode: 49, modifiers: control | shift, in: entries) == false)
    }

    @Test("A different combination is left alone")
    func leavesOtherCombinationsAlone() {
        let entries = SystemHotkeys.entries(from: plist([
            (id: "64", keyCode: 49, modifiers: 1048576, enabled: true)
        ]))
        #expect(SystemHotkeys.isClaimed(keyCode: 49, modifiers: control | option, in: entries) == false)
    }

    /// `NSEvent.ModifierFlags` carries bits the system list never sets, and a
    /// raw comparison would then miss every real collision.
    @Test("Modifier bits outside the four that matter are ignored")
    func ignoresIrrelevantModifierBits() {
        let entries = SystemHotkeys.entries(from: plist([
            (id: "156", keyCode: 49, modifiers: 262144 + 131072, enabled: true)
        ]))
        let withDeviceBits = control | shift | 0x100 | 0x20000000
        #expect(SystemHotkeys.isClaimed(keyCode: 49, modifiers: withDeviceBits, in: entries))
    }

    /// Rows without parameters exist in the real plist; they must not crash the
    /// parse or the whole check silently returns "nothing is taken".
    @Test("Malformed rows are skipped, not fatal")
    func skipsMalformedRows() {
        let entries = SystemHotkeys.entries(from: [
            "1": ["enabled": true],
            "2": "not a dictionary",
            "156": ["enabled": true, "value": ["parameters": [65535, 49, 393216]]],
        ])
        #expect(entries.count == 1)
        #expect(SystemHotkeys.isClaimed(keyCode: 49, modifiers: control | shift, in: entries))
    }

    /// The trigger the app ships with has to be one macOS does not reserve by
    /// default. ⌘Space and ⌥⌘Space are Spotlight; ⌃⇧Space was the bug.
    @Test("The shipped default avoids the combinations macOS reserves for Spotlight")
    func theDefaultTriggerAvoidsKnownSystemShortcuts() {
        let entries = SystemHotkeys.entries(from: plist([
            (id: "64", keyCode: 49, modifiers: 1048576, enabled: true),
            (id: "65", keyCode: 49, modifiers: 1048576 + 524288, enabled: true),
            (id: "156", keyCode: 49, modifiers: 262144 + 131072, enabled: true),
        ]))
        #expect(
            SystemHotkeys.isClaimed(
                keyCode: TouchlessActivationTrigger.keyCode,
                modifiers: TouchlessActivationTrigger.modifiers,
                in: entries
            ) == false
        )
    }
}
