import Foundation
import Testing
@testable import OpenIslandCore

struct MitamaOSURLTests {
    @Test func defaultWhenUnset() {
        #expect(MitamaOSURL.baseURL(nil) == MitamaOSURL.defaultURL)
    }

    @Test(arguments: ["http://example.com", "file:///tmp/hub", "javascript:alert(1)", "https://", "garbage", "https://user:password@example.com"])
    func rejectsInvalidSettings(_ value: String) {
        #expect(MitamaOSURL.baseURL(value) == MitamaOSURL.defaultURL)
    }

    @Test func acceptsHTTPSOverride() {
        #expect(MitamaOSURL.baseURL("https://hub.example.com/start").host == "hub.example.com")
    }

    @Test(arguments: ["", "decide", "https://evil.com", "//evil.com", "/\\evil.com", "/\n"])
    func rejectsUnsafePaths(_ path: String) {
        #expect(!MitamaOSURL.isValidPath(path))
        #expect(MitamaOSURL.url(base: MitamaOSURL.defaultURL, path: path).absoluteString == "https://mitama-os-hub.vercel.app/")
    }

    @Test(arguments: ["/", "/decide", "/decide/item"])
    func acceptsPaths(_ path: String) {
        #expect(MitamaOSURL.isValidPath(path))
        #expect(MitamaOSURL.url(base: MitamaOSURL.defaultURL, path: path).path == path || path == "/")
    }

    @Test func replacesConfiguredPathQueryAndFragment() {
        let base = MitamaOSURL.baseURL("https://example.com/start?q=1#fragment")
        #expect(MitamaOSURL.url(base: base, path: "/decide").absoluteString == "https://example.com/decide")
    }

    @Test(arguments: ["https://gmail.com", "https://mitama-os-hub.vercel.app.evil.com", "http://mitama-os-hub.vercel.app", "https://mitama-os-hub.vercel.app:444", "javascript:alert(1)"])
    func identifiesExternalURLs(_ value: String) {
        #expect(!MitamaOSURL.isInternal(URL(string: value)!, base: MitamaOSURL.defaultURL))
    }

    @Test func internalNavigationUsesConfiguredHost() {
        let base = MitamaOSURL.baseURL("https://custom.example.com")
        #expect(MitamaOSURL.isInternal(URL(string: "https://custom.example.com/decide")!, base: base))
        #expect(!MitamaOSURL.isInternal(MitamaOSURL.defaultURL, base: base))
    }

    @Test(arguments: [
        "https://mitama-os-hub.vercel.app/decide", "https://accounts.google.com/o/oauth2/v2/auth",
        "https://accounts.youtube.com/accounts/SetSID", "https://xxx.supabase.co/auth/v1/authorize",
    ])
    func allowsWindowAuthentication(_ value: String) {
        #expect(MitamaOSURL.isAllowedInWindow(URL(string: value)!, base: MitamaOSURL.defaultURL))
    }

    @Test(arguments: [
        "https://evil.com", "https://google.com/search?q=test", "https://www.google.com/oauth2/auth",
        "https://accounts.google.com.evil.com", "http://accounts.google.com", "javascript:alert(1)",
        "https://user:password@accounts.google.com", "https://user@xxx.supabase.co/auth/v1/authorize",
        "https://xxx.supabase.co/rest/v1/items", "https://xxx.supabase.co/auth/v10/authorize",
        "https://supabase.co/auth/v1/authorize", "https://xxx.supabase.co.evil.com/auth/v1/authorize",
        "https://accounts.google.com:444/oauth2/auth",
    ])
    func rejectsWindowAuthentication(_ value: String) {
        #expect(!MitamaOSURL.isAllowedInWindow(URL(string: value)!, base: MitamaOSURL.defaultURL))
    }

}
