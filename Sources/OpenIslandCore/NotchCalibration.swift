import CoreGraphics

/// A per-Mac correction for the notch rectangle macOS reports.
///
/// The reported size is right on most machines and a few points off on some,
/// which puts the closed island slightly beside the physical cutout. Rather than
/// carrying a table of models, the user nudges it.
public struct NotchCalibration: Equatable, Sendable {
    /// Zero means "trust macOS" — not "collapse the notch". Treating an unset
    /// override as a real zero would hide the island entirely.
    public var heightOverride: Double
    public var widthOverride: Double

    public init(heightOverride: Double = 0, widthOverride: Double = 0) {
        self.heightOverride = heightOverride
        self.widthOverride = widthOverride
    }

    public var isIdentity: Bool { heightOverride <= 0 && widthOverride <= 0 }

    public func apply(to measured: CGSize) -> CGSize {
        CGSize(
            width: widthOverride > 0 ? widthOverride : measured.width,
            height: heightOverride > 0 ? heightOverride : measured.height
        )
    }
}
