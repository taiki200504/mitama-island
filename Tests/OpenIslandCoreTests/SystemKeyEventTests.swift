import Testing
@testable import OpenIslandCore

@Suite("SystemKeyEvent decoding")
struct SystemKeyEventTests {
    /// Builds the `data1` payload the way a real `NSEvent.data1` carries it
    /// for a subtype-8 system-defined event.
    private func data1(keyCode: Int, isDown: Bool, isRepeat: Bool) -> Int {
        let state = isDown ? 0xA : 0xB
        return (keyCode << 16) | (state << 8) | (isRepeat ? 1 : 0)
    }

    @Test(
        "Every key code this app acts on decodes to its key",
        arguments: [
            (0, SystemKey.volumeUp),
            (1, SystemKey.volumeDown),
            (2, SystemKey.brightnessUp),
            (3, SystemKey.brightnessDown),
            (7, SystemKey.mute),
            (21, SystemKey.keyboardBacklightUp),
            (22, SystemKey.keyboardBacklightDown),
        ]
    )
    func decodesKnownKeyCodes(keyCode: Int, expected: SystemKey) {
        let decoded = SystemKeyEvent.decode(subtype: 8, data1: data1(keyCode: keyCode, isDown: true, isRepeat: false))
        #expect(decoded?.key == expected)
    }

    @Test("An unrecognized key code decodes to nil")
    func unknownKeyCodeIsNil() {
        let decoded = SystemKeyEvent.decode(subtype: 8, data1: data1(keyCode: 99, isDown: true, isRepeat: false))
        #expect(decoded == nil)
    }

    @Test("A subtype other than 8 (system-defined media keys) decodes to nil regardless of the key code")
    func wrongSubtypeIsNil() {
        let decoded = SystemKeyEvent.decode(subtype: 1, data1: data1(keyCode: 0, isDown: true, isRepeat: false))
        #expect(decoded == nil)
    }

    @Test("Key-up is decoded, not dropped — isDown is what tells the two apart")
    func keyUpIsDecodedWithIsDownFalse() {
        let down = SystemKeyEvent.decode(subtype: 8, data1: data1(keyCode: 0, isDown: true, isRepeat: false))
        let up = SystemKeyEvent.decode(subtype: 8, data1: data1(keyCode: 0, isDown: false, isRepeat: false))
        #expect(down?.isDown == true)
        #expect(up?.isDown == false)
    }

    @Test("The repeat flag is carried through independently of key state")
    func repeatFlagIsCarried() {
        let repeated = SystemKeyEvent.decode(subtype: 8, data1: data1(keyCode: 0, isDown: true, isRepeat: true))
        let notRepeated = SystemKeyEvent.decode(subtype: 8, data1: data1(keyCode: 0, isDown: true, isRepeat: false))
        #expect(repeated?.isRepeat == true)
        #expect(notRepeated?.isRepeat == false)
    }
}
