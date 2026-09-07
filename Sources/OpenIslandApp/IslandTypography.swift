import AppKit
import CoreText
import OSLog
import SwiftUI

private let fontRegistrationLog = Logger(subsystem: "com.mitama.island", category: "typography")

/// The island's monospaced and display typefaces.
///
/// The reference product ships Departure Mono, a pixel-grid face that is what
/// makes its numbers and badges read as part of the island rather than as
/// ordinary UI text. Rajdhani is the crystal-HUD grammar's display face for
/// caps headlines. Both are free under the SIL Open Font License, so this
/// bundles them rather than approximating with system fonts.
///
/// Registration can fail — a corrupt copy, a sandbox refusal — so every call
/// site falls back to a system face rather than losing the text.
enum IslandTypography {
    static let departureMonoName = "Departure Mono"
    static let displayFontName = "Rajdhani-SemiBold"

    /// Every bundled face this app registers at launch, as
    /// (resource name, file extension) pairs.
    private static let bundledFonts: [(resource: String, ext: String)] = [
        ("DepartureMono-Regular", "otf"),
        ("Rajdhani-SemiBold", "ttf"),
        ("Rajdhani-Medium", "ttf"),
    ]

    /// The resource names that registered successfully. Lazily computed once,
    /// on first access, the way any static stored property is. A failure here
    /// is silent to callers — they just get the system-font fallback — so it
    /// is logged instead, or a missing font in a shipped build has no trace.
    private static let registeredResources: Set<String> = {
        var succeeded: Set<String> = []
        for font in bundledFonts {
            if registerBundledFont(resource: font.resource, ext: font.ext) {
                succeeded.insert(font.resource)
            } else {
                fontRegistrationLog.error("Failed to register bundled font \(font.resource, privacy: .public).\(font.ext, privacy: .public)")
            }
        }
        return succeeded
    }()

    /// Registers every bundled font. Callers don't need the result — reading
    /// it is enough to trigger registration — but it is useful in tests.
    /// `true` only when every bundled font registered; a partial failure
    /// still logs which one, but callers asking "did this fully work" should
    /// not be told yes when only some fonts are actually usable.
    @discardableResult
    static func registerBundledFonts() -> Bool {
        registeredResources.count == bundledFonts.count
    }

    /// A monospaced font at the given size, preferring the bundled face.
    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard registeredResources.contains("DepartureMono-Regular") else {
            return .system(size: size, weight: weight, design: .monospaced)
        }
        return .custom(departureMonoName, fixedSize: size)
    }

    /// AppKit variant, for the few places that draw outside SwiftUI.
    static func nsMono(size: CGFloat) -> NSFont {
        guard registeredResources.contains("DepartureMono-Regular"),
              let font = NSFont(name: departureMonoName, size: size) else {
            return .monospacedSystemFont(ofSize: size, weight: .regular)
        }
        return font
    }

    /// The display face for a headline set in caps — Rajdhani where it
    /// registered, the system semibold face otherwise.
    static func display(size: CGFloat) -> Font {
        guard registeredResources.contains("Rajdhani-SemiBold") else {
            return .system(size: size, weight: .semibold)
        }
        return .custom(displayFontName, fixedSize: size)
    }

    /// Whether `text` is entirely Latin script (ASCII, Latin-1 Supplement,
    /// Latin Extended-A/B, and their combining marks).
    ///
    /// Rajdhani has no CJK glyphs, and `.textCase(.uppercase)` has no meaning
    /// for a script without case — `saoCaps` uses this to fall back to the
    /// system font for a localized string that turned out not to be Latin.
    static func isLatinScript(_ text: String) -> Bool {
        !text.unicodeScalars.contains { $0.value > 0x036F }
    }

    @discardableResult
    private static func registerBundledFont(resource: String, ext: String) -> Bool {
        guard let url = Bundle.appResources.url(
            forResource: resource,
            withExtension: ext,
            subdirectory: "Fonts"
        ) ?? Bundle.appResources.url(forResource: resource, withExtension: ext) else {
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

extension View {
    /// A caps headline in the crystal-HUD's display face: Rajdhani,
    /// uppercased, tracked out proportionally to size.
    ///
    /// Only for text already known to be Latin — a fixed English token, or a
    /// string checked with `IslandTypography.isLatinScript` first. Rajdhani
    /// has no CJK glyphs and uppercase has no meaning outside Latin/Cyrillic/
    /// Greek scripts, so forcing this onto a localized string that turned out
    /// to be Japanese or Chinese would silently drop the text.
    func saoCaps(size: CGFloat) -> some View {
        self
            .font(IslandTypography.display(size: size))
            .textCase(.uppercase)
            .tracking(SAOGrammar.tracking(for: size))
    }

    /// Content-aware variant for a localized string that might not be Latin —
    /// a session-section header or card title, whose text changes with the
    /// app's language. Falls back to a plain system headline instead of
    /// uppercasing CJK into nothing.
    @ViewBuilder
    func saoCaps(size: CGFloat, text: String) -> some View {
        if IslandTypography.isLatinScript(text) {
            saoCaps(size: size)
        } else {
            font(.system(size: size, weight: .semibold))
        }
    }
}
