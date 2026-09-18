import CoreGraphics
import Foundation

/// Wraps the private `DisplayServices` framework's brightness get/set — no
/// public API exposes built-in display brightness at all, which is why every
/// third-party brightness tool on macOS resorts to the same private symbols.
///
/// Fails open: if `dlopen`/`dlsym` cannot find what this expects (a future
/// macOS renaming or removing them), `isAvailable` is `false` and the
/// coordinator lets brightness keys pass through untouched — macOS's own OSD
/// keeps working for a key this app turns out unable to act on, rather than
/// the key going silent.
@MainActor
final class DisplayBrightnessControl: BrightnessControlling {
    private typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    let isAvailable: Bool
    private let getBrightness: GetBrightnessFn?
    private let setBrightnessFn: SetBrightnessFn?

    init() {
        guard
            let handle = dlopen(
                "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                RTLD_NOW
            ),
            let getSymbol = dlsym(handle, "DisplayServicesGetBrightness"),
            let setSymbol = dlsym(handle, "DisplayServicesSetBrightness")
        else {
            getBrightness = nil
            setBrightnessFn = nil
            isAvailable = false
            return
        }

        getBrightness = unsafeBitCast(getSymbol, to: GetBrightnessFn.self)
        setBrightnessFn = unsafeBitCast(setSymbol, to: SetBrightnessFn.self)
        isAvailable = true
    }

    func currentBrightness() -> Double? {
        guard isAvailable, let getBrightness else { return nil }
        var value: Float = 0
        guard getBrightness(CGMainDisplayID(), &value) == 0 else { return nil }
        return Double(value)
    }

    func setBrightness(_ level: Double) {
        guard isAvailable, let setBrightnessFn else { return }
        _ = setBrightnessFn(CGMainDisplayID(), Float(min(max(0, level), 1)))
    }
}
