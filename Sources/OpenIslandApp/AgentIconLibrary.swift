import AppKit
import Foundation
import OpenIslandCore

/// Official brand marks for each agent, when the user has fetched them.
///
/// The images are deliberately **not** part of this repository. They are other
/// companies' trademarks, and a GPLv3 fork is not a place to redistribute them.
/// `scripts/fetch-agent-icons.sh` pulls them from each vendor's own
/// distribution into a gitignored folder; without that step the island keeps
/// using its own pixel marks, which is a complete look rather than a degraded
/// one.
@MainActor
struct AgentIconLibrary {
    static let shared = AgentIconLibrary()

    /// Alongside the app so a fetched set survives a rebuild of the package.
    static func defaultDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: "MitamaIsland/AgentIcons")
    }

    let directory: URL

    init(directory: URL = AgentIconLibrary.defaultDirectory()) {
        self.directory = directory
    }

    /// File stem expected for each agent, matching what the fetch script writes.
    static func fileStem(for tool: AgentTool) -> String { tool.rawValue }

    /// Whether any brand mark at all is present, which decides whether the
    /// appearance choice is offered or explained away.
    var hasAnyIcon: Bool {
        AgentTool.allCases.contains { image(for: $0) != nil }
    }

    func image(for tool: AgentTool) -> NSImage? {
        let stem = Self.fileStem(for: tool)
        for ext in ["png", "pdf", "svg"] {
            let url = directory.appending(path: "\(stem).\(ext)")
            guard FileManager.default.fileExists(atPath: url.path),
                  let image = NSImage(contentsOf: url) else { continue }
            image.isTemplate = false
            return image
        }
        return nil
    }
}

/// Which set of marks the island draws.
enum AgentIconStyle: String, CaseIterable, Identifiable, Sendable {
    /// The app's own pixel marks. Always available.
    case pixel
    /// Each vendor's official logo, if fetched.
    case brand

    var id: String { rawValue }
    var labelKey: String { "settings.appearance.agentIcon.\(rawValue)" }
}
