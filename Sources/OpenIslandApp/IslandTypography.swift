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

extension IslandTypography {
    /// The sizes in the panel were measured against the reference product one by
    /// one, so they are not collapsed into a scale — doing that would undo that
    /// work for no gain. The content-size setting multiplies them instead.
    static func scaled(_ size: CGFloat, by scale: CGFloat) -> CGFloat {
        // No rounding: the measured sizes are already fractional (11.2, 12.2),
        // and snapping them changed the default rendering.
        size * min(max(scale, 0.75), 1.6)
    }

    @MainActor
    static var contentScale: CGFloat {
        let configured = SettingsStore.shared.display.contentFontSize
        return configured / DisplaySettings.Defaults.contentFontSize
    }

    @MainActor
    static func scaled(_ size: CGFloat) -> CGFloat {
        scaled(size, by: contentScale)
    }
}

extension Font {
    /// Drop-in replacement for `.system(size:weight:design:.monospaced)`, sized
    /// by the content-size setting.
    @MainActor
    static func islandMono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        IslandTypography.mono(size: IslandTypography.scaled(size), weight: weight)
    }

    /// Drop-in replacement for `.system(size:weight:)` inside the island.
    @MainActor
    static func islandText(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: IslandTypography.scaled(size), weight: weight)
    }
}
