import Foundation

/// Wraps the private CoreBrightness `KeyboardBrightnessClient` through the
/// Objective-C runtime and key-value coding, which bridges its scalar
/// `brightness` property without needing an `NSInvocation`.
///
/// Off by default (`HUDSettings.keyboardBacklight`) even once the master
/// switch is on: of the three meters this one is the most likely to shift
/// between macOS versions, so it stays opt-in on top of Accessibility.
///
/// Fails open exactly like `DisplayBrightnessControl`: unavailable rather
/// than swallowing a key it cannot actually act on.
@MainActor
final class KeyboardBacklightControl: KeyboardBacklightControlling {
    let isAvailable: Bool
    private let client: NSObject?

    init() {
        guard
            dlopen(
                "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness",
                RTLD_NOW
            ) != nil,
            let clientClass = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type
        else {
            client = nil
            isAvailable = false
            return
        }

        let instance = clientClass.init()
        guard
            instance.responds(to: Selector(("brightness"))),
            instance.responds(to: Selector(("setBrightness:")))
        else {
            client = nil
            isAvailable = false
            return
        }

        client = instance
        isAvailable = true
    }

    func currentLevel() -> Double? {
        guard isAvailable, let client else { return nil }
        return (client.value(forKey: "brightness") as? NSNumber)?.doubleValue
    }

    func setLevel(_ level: Double) {
        guard isAvailable, let client else { return }
        client.setValue(NSNumber(value: min(max(0, level), 1)), forKey: "brightness")
    }
}
