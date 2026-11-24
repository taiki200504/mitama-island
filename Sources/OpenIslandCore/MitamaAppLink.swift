import Foundation

/// Deep link into the native mitama app (/Applications/mitama.app).
public enum MitamaAppLink {
    public static let bundleIdentifier = "app.mitama.os.mac"
    public static let scheme = "app.mitama.os.mac"

    /// `app.mitama.os.mac://open?path=/notifications`. An invalid path falls back to "/".
    public static func url(path: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "path", value: MitamaOSURL.isValidPath(path) ? path : "/")]
        return components.url!
    }
}
