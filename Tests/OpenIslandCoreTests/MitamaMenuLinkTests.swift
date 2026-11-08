import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Mitama menu link")
struct MitamaMenuLinkTests {
    @Test("the link matches what the new menu app registers")
    func linkShape() {
        // mitama-os 側 MenuOpenLink.scheme / host と同じ。片方だけ変えると島からメニューが開かなくなる。
        #expect(MitamaMenuLink.url.absoluteString == "app.mitama.os.mac.menu://open")
        #expect(MitamaMenuLink.url.scheme == MitamaMenuLink.scheme)
        #expect(MitamaMenuLink.url.host == "open")
    }

    @Test("the button is offered only when something can open the link")
    func offerOnlyWhenInstalled() {
        #expect(MitamaMenuLink.shouldOffer(applicationURL: nil) == false)
        #expect(MitamaMenuLink.shouldOffer(applicationURL: URL(fileURLWithPath: "/Applications/MitamaMac.app")))
    }
}
