import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

@Suite("Agent icon library")
@MainActor
struct AgentIconLibraryTests {
    /// The state every user is in until they run the fetch script. It must read
    /// as "no icons", never as a crash or an empty image.
    @Test("An unfetched library reports nothing")
    func emptyLibrary() {
        let library = AgentIconLibrary(
            directory: URL(filePath: "/nonexistent/\(UUID().uuidString)")
        )
        #expect(library.hasAnyIcon == false)
        for tool in AgentTool.allCases {
            #expect(library.image(for: tool) == nil)
        }
    }

    /// The script writes files named after the raw value; if that mapping ever
    /// drifts, every icon silently stops resolving.
    @Test("File names follow the agent's raw value")
    func fileStemsMatchRawValues() {
        for tool in AgentTool.allCases {
            #expect(AgentIconLibrary.fileStem(for: tool) == tool.rawValue)
        }
    }

    @Test("An unknown stored style falls back to the pixel marks")
    func unknownStyleFallsBack() {
        #expect(AgentIconStyle(rawValue: "hologram") == nil)
    }
}
