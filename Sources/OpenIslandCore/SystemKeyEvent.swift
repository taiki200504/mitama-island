import Foundation

/// A hardware media key macOS delivers as an `NSSystemDefined` event rather
/// than an ordinary key event — volume, mute, brightness, and the keyboard
/// backlight all arrive this way instead of through `NSEvent.KeyCode`.
public enum SystemKey: Sendable, Equatable, CaseIterable {
    case volumeUp
    case volumeDown
    case mute
    case brightnessUp
    case brightnessDown
    case keyboardBacklightUp
    case keyboardBacklightDown
}

/// Decodes the `data1` payload of an `NX_SYSDEFINED` (subtype 8) event into a
/// `SystemKey` plus its up/down and repeat flags.
///
/// Bit layout of `data1` for subtype 8, as `NSEvent`'s system-defined events
/// carry it:
/// - bits 16...31 — the key code
/// - bits 8...15 — the key state (`0xA` down, `0xB` up)
/// - bit 0 — set while the key is being auto-repeated
public enum SystemKeyEvent {
    private static let keyCodesByRawValue: [Int: SystemKey] = [
        0: .volumeUp,
        1: .volumeDown,
        2: .brightnessUp,
        3: .brightnessDown,
        7: .mute,
        21: .keyboardBacklightUp,
        22: .keyboardBacklightDown,
    ]

    /// `nil` for anything other than a subtype-8 media key this app acts on —
    /// including every other `NX_SYSDEFINED` subtype and any key code not in
    /// the table above.
    public static func decode(subtype: Int, data1: Int) -> (key: SystemKey, isDown: Bool, isRepeat: Bool)? {
        guard subtype == 8 else { return nil }
        let keyCode = (data1 >> 16) & 0xFFFF
        guard let key = keyCodesByRawValue[keyCode] else { return nil }
        let keyState = (data1 & 0xFF00) >> 8
        let isDown = keyState == 0xA
        let isRepeat = data1 & 0x1 != 0
        return (key, isDown, isRepeat)
    }
}

/// Which of the three system meters a HUD gauge is showing.
public enum HUDGauge: Sendable, Equatable, CaseIterable {
    case volume
    case brightness
    case keyboardBacklight
}

/// The stepping grid every HUD gauge press moves along: 1/16 of the range per
/// plain press, 1/64 with the fine modifier held — the same two granularities
/// macOS itself steps these keys at.
public enum HUDStepper {
    public static let coarseStep: Double = 1.0 / 16.0
    public static let fineStep: Double = 1.0 / 64.0
    private static let totalSegments = 16

    /// `level` moved one step in `direction` (positive up, negative down) on
    /// the grid `fine` selects, clamped to 0...1.
    ///
    /// An off-grid `level` (a device's current level rarely sits exactly on
    /// one of these stops) snaps to the *next* grid line in the direction of
    /// travel — up rounds up, down rounds down — rather than to whichever
    /// stop is nearest: nearest-of-`level + step` can overshoot by an extra
    /// stop whenever `level` already sits more than half a step into the
    /// cell it is leaving. A `level` already exactly on the grid instead
    /// advances one full step, or every press from an on-grid level would be
    /// a no-op.
    public static func next(level: Double, direction: Int, fine: Bool) -> Double {
        let clampedLevel = min(max(0, level), 1)
        guard direction != 0 else { return clampedLevel }

        let step = fine ? fineStep : coarseStep
        let position = clampedLevel / step
        let nextPosition: Double = if direction > 0 {
            let ceiled = position.rounded(.up)
            ceiled == position ? ceiled + 1 : ceiled
        } else {
            let floored = position.rounded(.down)
            floored == position ? floored - 1 : floored
        }

        return min(max(0, nextPosition * step), 1)
    }

    /// How many of 16 segments `level` fills — the discrete look the HUD
    /// gauge draws, as opposed to a continuous fraction.
    public static func segments(level: Double) -> Int {
        let clamped = min(max(0, level), 1)
        return Int((clamped * Double(totalSegments)).rounded())
    }
}
