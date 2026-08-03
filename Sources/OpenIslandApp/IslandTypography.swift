import AppKit
import CoreText
import SwiftUI

/// The island's monospaced typeface.
///
/// The reference product ships Departure Mono, a pixel-grid face that is what
/// makes its numbers and badges read as part of the island rather than as
/// ordinary UI text. It is free under the SIL Open Font License, so this bundles
/// it rather than approximating with the system monospace.
///
/// Registration can fail — a corrupt copy, a sandbox refusal — so every call
/// site falls back to the system monospaced face rather than losing the text.
enum IslandTypography {
    static let departureMonoName = "Departure Mono"

    private static let isRegistered: Bool = registerBundledFont()

    /// A monospaced font at the given size, preferring the bundled face.
    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard isRegistered else {
            return .system(size: size, weight: weight, design: .monospaced)
        }
        return .custom(departureMonoName, fixedSize: size)
    }

    /// AppKit variant, for the few places that draw outside SwiftUI.
    static func nsMono(size: CGFloat) -> NSFont {
        guard isRegistered, let font = NSFont(name: departureMonoName, size: size) else {
            return .monospacedSystemFont(ofSize: size, weight: .regular)
        }
        return font
    }

    @discardableResult
    private static func registerBundledFont() -> Bool {
        guard let url = Bundle.module.url(
            forResource: "DepartureMono-Regular",
            withExtension: "otf",
            subdirectory: "Fonts"
        ) ?? Bundle.module.url(forResource: "DepartureMono-Regular", withExtension: "otf") else {
            return false
        }

        var error: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        if !registered {
            // Already registered by an earlier launch in the same process is a
            // success as far as callers are concerned.
            let code = CFErrorGetCode(error?.takeUnretainedValue())
            return code == CTFontManagerError.alreadyRegistered.rawValue
        }
        return true
    }
}

extension Font {
    /// Drop-in replacement for `.system(size:weight:design:.monospaced)`.
    static func islandMono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        IslandTypography.mono(size: size, weight: weight)
    }
}
