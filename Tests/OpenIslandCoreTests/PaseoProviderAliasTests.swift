import Foundation
import Testing
@testable import OpenIslandCore

struct PaseoProviderAliasTests {
    @Test func customProvidersAreReadFromAgentsProviders() {
        let config = #"""
        {"agents":{"providers":{
          "auto":{"extends":"claude","label":"自動"},
          "grok":{"extends":"acp","command":["grok"]},
          "opencode":{"env":{"A":"1"}}
        }}}
        """#
        let aliases = PaseoProviderAliases.aliases(fromConfig: Data(config.utf8))
        #expect(aliases == ["auto": "claude", "grok": "acp"])
        #expect(PaseoProviderAliases.canonical("auto", aliases: aliases) == "claude")
    }

    @Test func unreadableConfigYieldsNoAliases() {
        #expect(PaseoProviderAliases.aliases(fromConfig: Data("{".utf8)).isEmpty)
        #expect(PaseoProviderAliases.canonical("auto", aliases: [:]) == nil)
    }
}
