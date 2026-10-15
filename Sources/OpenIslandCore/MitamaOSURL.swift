import Foundation

/// URL policy shared by the embedded Hub and its navigation delegate.
public enum MitamaOSURL {
    public static let defaultURL = URL(string: "https://mitama-os-hub.vercel.app")!

    public static func baseURL(_ setting: String?) -> URL {
        guard let setting, let url = URL(string: setting),
              url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return defaultURL }
        return url
    }

    public static func isValidPath(_ path: String) -> Bool {
        path.hasPrefix("/") && !path.hasPrefix("//")
            && !path.contains("\\") && !path.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    public static func url(base: URL, path: String) -> URL {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.path = isValidPath(path) ? path : "/"
        components.query = nil
        components.fragment = nil
        return components.url!
    }

    public static func isInternal(_ url: URL, base: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == base.host?.lowercased()
            && url.port == base.port && url.user == nil && url.password == nil
    }

    /// HTTPS destinations allowed inside the Hub, including its sign-in flow.
    public static func isAllowedInWindow(_ url: URL, base: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil,
              let host = url.host?.lowercased() else { return false }
        if isInternal(url, base: base) { return true }
        guard url.port == nil || url.port == 443 else { return false }
        if host == "accounts.google.com" || host == "accounts.youtube.com" { return true }
        return host.hasSuffix(".supabase.co") && url.path.hasPrefix("/auth/v1/")
    }

}
