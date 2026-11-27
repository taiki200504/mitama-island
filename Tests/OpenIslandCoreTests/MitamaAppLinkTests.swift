import Foundation
import Testing
@testable import OpenIslandCore

struct MitamaAppLinkTests {
    @Test func buildsMenuOpenURL() {
        #expect(MitamaAppLink.menuOpenURL.absoluteString == "app.mitama.os.mac.menu://open")
    }

    @Test func buildsOpenURLWithPath() {
        #expect(MitamaAppLink.url(path: "/notifications").absoluteString == "app.mitama.os.mac://open?path=/notifications")
    }

    @Test(arguments: ["", "//evil.com", "notifications", "/a\\b"])
    func invalidPathFallsBackToRoot(path: String) {
        #expect(MitamaAppLink.url(path: path).absoluteString == "app.mitama.os.mac://open?path=/")
    }
}
