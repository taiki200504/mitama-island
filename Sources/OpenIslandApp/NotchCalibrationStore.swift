import Foundation
import OpenIslandCore

extension NotchCalibration {
    /// Read straight from `UserDefaults` rather than threaded through the model.
    ///
    /// `NSScreen.notchSize` is called from geometry code that has no model in
    /// hand, and the values are two doubles read a handful of times per layout.
    /// Passing them down every call site would cost more than it buys.
    static var current: NotchCalibration {
        let defaults = UserDefaults.standard
        return NotchCalibration(
            heightOverride: defaults.double(forKey: DisplaySettings.Keys.notchHeightOverride),
            widthOverride: defaults.double(forKey: DisplaySettings.Keys.notchWidthOverride)
        )
    }
}
