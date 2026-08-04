import CoreGraphics
import Testing
@testable import OpenIslandCore

@Suite("Notch calibration")
struct NotchCalibrationTests {
    private let measured = CGSize(width: 200, height: 38)

    /// The failure this guards against: an unset override is stored as 0, and
    /// treating that as a real measurement collapses the island to nothing.
    @Test("Zero means trust macOS, not a zero-sized notch")
    func zeroIsIdentity() {
        let calibration = NotchCalibration()
        #expect(calibration.isIdentity)
        #expect(calibration.apply(to: measured) == measured)
    }

    @Test("A negative value is also ignored")
    func negativeIsIdentity() {
        let calibration = NotchCalibration(heightOverride: -10, widthOverride: -1)
        #expect(calibration.apply(to: measured) == measured)
    }

    @Test("Each dimension overrides independently")
    func overridesIndependently() {
        #expect(
            NotchCalibration(heightOverride: 44).apply(to: measured)
                == CGSize(width: 200, height: 44)
        )
        #expect(
            NotchCalibration(widthOverride: 210).apply(to: measured)
                == CGSize(width: 210, height: 38)
        )
        #expect(
            NotchCalibration(heightOverride: 44, widthOverride: 210).apply(to: measured)
                == CGSize(width: 210, height: 44)
        )
    }
}
