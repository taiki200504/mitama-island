import Carbon.HIToolbox
import Foundation

/// Turns a character the user typed into the settings into a virtual key code.
///
/// Virtual key codes are positions on the keyboard, not letters. On a French
/// AZERTY layout the key that produces "A" sits where a US keyboard has "Q", so
/// registering the US code for "A" would give a French user the wrong key. This
/// asks the active input source what each key actually produces.
struct KeycodeResolver {
    /// Every code a physical keyboard can report for a letter or digit. Scanning
    /// this range and asking what each produces is cheap enough to do once per
    /// layout, and it needs no table of our own.
    private static let scannedKeyCodes: ClosedRange<UInt16> = 0...127

    private let table: [String: UInt16]

    init(table: [String: UInt16]) {
        self.table = table
    }

    /// Reads the layout currently selected in the menu bar.
    init(inputSource: TISInputSource? = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()) {
        self.table = Self.buildTable(for: inputSource) ?? Self.usFallbackTable
    }

    /// The key code that produces `character` on this layout, or `nil` when the
    /// layout has no such key at all — some layouts genuinely lack a "Q".
    func keyCode(for character: String) -> UInt16? {
        let normalised = character.trimmingCharacters(in: .whitespaces).uppercased()
        guard normalised.count == 1 else { return nil }
        return table[normalised]
    }

    var isEmpty: Bool { table.isEmpty }

    // MARK: Layout reading

    private static func buildTable(for inputSource: TISInputSource?) -> [String: UInt16]? {
        guard let inputSource,
              let layoutData = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData)
        else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data

        var table: [String: UInt16] = [:]
        data.withUnsafeBytes { buffer in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return
            }
            for keyCode in scannedKeyCodes {
                guard let produced = character(for: keyCode, layout: layout), produced.count == 1 else {
                    continue
                }
                let upper = produced.uppercased()
                guard upper.first?.isLetter == true || upper.first?.isNumber == true else { continue }
                // First key wins: a layout can produce the same letter from two
                // keys, and the lower code is the primary one.
                if table[upper] == nil { table[upper] = keyCode }
            }
        }
        return table.isEmpty ? nil : table
    }

    private static func character(
        for keyCode: UInt16,
        layout: UnsafePointer<UCKeyboardLayout>
    ) -> String? {
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0

        let status = UCKeyTranslate(
            layout,
            keyCode,
            UInt16(kUCKeyActionDisplay),
            0, // no modifiers: we want the unshifted legend
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }

    /// Used when the layout cannot be read at all — a non-Unicode input source
    /// such as some Chinese or Japanese methods returns no layout data. A US
    /// keyboard is a better guess than giving up on shortcuts entirely.
    static let usFallbackTable: [String: UInt16] = [
        "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7,
        "C": 8, "V": 9, "B": 11, "Q": 12, "W": 13, "E": 14, "R": 15,
        "Y": 16, "T": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "9": 25, "7": 26, "8": 28, "0": 29, "O": 31, "U": 32,
        "I": 34, "P": 35, "L": 37, "J": 38, "K": 40, "N": 45, "M": 46
    ]
}
