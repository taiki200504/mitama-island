import Foundation

/// Manages app-level language preference and provides localized string lookup.
///
/// Views that read ``t(_:)`` or ``t(_:_:)`` will re-render when ``language``
/// changes because `bundle` is an `@Observable` tracked property.
@Observable
final class LanguageManager: @unchecked Sendable {
    static let shared = LanguageManager()

    // MARK: - Language enum

    enum AppLanguage: String, CaseIterable, Identifiable, Codable {
        case system
        case en
        case ja
        case zhHans = "zh-Hans"
        case zhHant = "zh-Hant"

        var id: String { rawValue }

        /// Resolve to a concrete language code (not "system").
        var resolvedCode: String {
            switch self {
            case .system:
                let preferred = Locale.preferredLanguages.first ?? "en"
                if preferred.hasPrefix("zh-Hant") || preferred.hasPrefix("zh-TW") || preferred.hasPrefix("zh-HK") || preferred.hasPrefix("zh-MO") {
                    return "zh-Hant"
                }
                if preferred.hasPrefix("zh") { return "zh-Hans" }
                if preferred.hasPrefix("ja") { return "ja" }
                return "en"
            case .en:
                return "en"
            case .ja:
                return "ja"
            case .zhHans:
                return "zh-Hans"
            case .zhHant:
                return "zh-Hant"
            }
        }
    }

    // MARK: - State

    var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey)
            reloadBundle()
        }
    }

    private(set) var bundle: Bundle

    // MARK: - Init

    private static let defaultsKey = "appLanguage"

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? "system"
        let lang = AppLanguage(rawValue: saved) ?? .system
        self.language = lang
        self.bundle = Self.resolveBundle(for: lang)
    }

    // MARK: - Localized string access

    /// Look up a localized string by key.
    func t(_ key: String) -> String {
        if key == "app.name" { return Self.applicationName }
        let value = hudVariant(of: key)
            ?? bundle.localizedString(forKey: key, value: key, table: nil)
        return Self.substitutingApplicationName(in: value)
    }

    /// Fills in `{app}` wherever a string names this app.
    ///
    /// The name used to be written out in every translation, and the UI went on
    /// saying "Open Island" for months after the app shipped as "Mitama Island".
    /// One substitution here is what keeps a rename from having to find them all
    /// again.
    private static func substitutingApplicationName(in value: String) -> String {
        guard value.contains("{app}") else { return value }
        return value.replacingOccurrences(of: "{app}", with: applicationName)
    }

    /// The HUD theme's wording for a key, if there is one.
    ///
    /// Rather than a second switch next to the theme, the voice follows it: one
    /// choice changes the whole personality. Only keys that actually have a
    /// `<key>.hud` entry change, so the scope is exactly the set of variants
    /// that were written — settings panes and error messages stay plain because
    /// no variant was added for them.
    private func hudVariant(of key: String) -> String? {
        guard Self.usesHUDVoice else { return nil }
        let hudKey = key + ".hud"
        let value = bundle.localizedString(forKey: hudKey, value: hudKey, table: nil)
        return value == hudKey ? nil : value
    }

    /// Read straight from defaults rather than through `DisplaySettings`, which
    /// is main-actor isolated while this is not.
    private static var usesHUDVoice: Bool {
        let raw = UserDefaults.standard.string(forKey: DisplaySettings.Keys.theme)
        return (raw ?? IslandThemeID.hud.rawValue) == IslandThemeID.hud.rawValue
    }

    /// The name the app is actually installed under.
    ///
    /// Read from the bundle rather than translated: it is a proper noun, and a
    /// hard-coded copy drifts silently when the bundle is renamed — the UI said
    /// "Open Island" long after the app shipped as "Mitama Island".
    static let applicationName: String = {
        let info = Bundle.main.infoDictionary
        let name = (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        // The fallback only fires where there is no app bundle to ask — under
        // `swift test`, mainly. It used to be the upstream project's name,
        // which meant the one place that could not read the real name confidently
        // reported the wrong one.
        return (trimmed?.isEmpty == false ? trimmed! : "Mitama Island")
    }()

    /// Look up a localized format string and apply arguments.
    func t(_ key: String, _ args: any CVarArg...) -> String {
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        return String(format: format, arguments: args)
    }

    // MARK: - Private

    private func reloadBundle() {
        bundle = Self.resolveBundle(for: language)
    }

    private static func resolveBundle(for language: AppLanguage) -> Bundle {
        let code = language.resolvedCode

        // Bundle.appResources is auto-generated by SPM when resources are declared.
        // SPM `.process()` may lowercase lproj directory names (e.g. "zh-Hans" → "zh-hans"),
        // and Bundle.path(forResource:ofType:) is case-sensitive, so try both variants.
        for candidate in [code, code.lowercased()] {
            if let path = Bundle.appResources.path(forResource: candidate, ofType: "lproj"),
               let localized = Bundle(path: path) {
                return localized
            }
        }

        // Fallback to English
        for candidate in ["en", "En"] {
            if let path = Bundle.appResources.path(forResource: candidate, ofType: "lproj"),
               let localized = Bundle(path: path) {
                return localized
            }
        }

        return Bundle.appResources
    }
}
