import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Diagnostics report")
struct DiagnosticsReportTests {
    private func makeReport(
        sessions: [DiagnosticsReport.SessionLine] = [],
        agents: [String] = ["Claude Code"],
        quiet: [String] = []
    ) -> DiagnosticsReport {
        DiagnosticsReport(
            appVersion: "1.15.0",
            systemVersion: "Version 15.0",
            installedAgents: agents,
            sessions: sessions,
            activeFilterCount: 2,
            quietScenes: quiet,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    @Test("The report names the app, the OS and the agents")
    func includesTheBasics() {
        let text = makeReport().rendered()
        #expect(text.contains("1.15.0"))
        #expect(text.contains("Version 15.0"))
        #expect(text.contains("Claude Code"))
    }

    /// The whole point of the file is deciding whether hooks are firing, so a
    /// filtered-out session has to be distinguishable from a missing one.
    @Test("Sessions say whether they reach the island")
    func showsVisibility() {
        let text = makeReport(sessions: [
            .init(tool: "Codex", phase: "running", terminalApp: "Ghostty", isVisible: false, updatedSecondsAgo: 12)
        ]).rendered()
        #expect(text.contains("Codex"))
        #expect(text.contains("filtered out"))
        #expect(text.contains("Ghostty"))
    }

    /// A report holding a client's repository path is one nobody dares send.
    /// Nothing that could carry a private name may appear.
    @Test("No paths, prompts or titles are included")
    func carriesNothingPrivate() {
        let text = makeReport(sessions: [
            .init(tool: "Codex", phase: "running", terminalApp: "Ghostty", isVisible: true, updatedSecondsAgo: 1)
        ]).rendered()
        #expect(!text.contains("/Users/"))
        #expect(!text.contains("~/"))
        #expect(text.contains("No working directories"))
    }

    @Test("An empty machine still produces a readable report")
    func emptyState() {
        let text = makeReport(agents: []).rendered()
        #expect(text.contains("agents installed (0)"))
        #expect(text.contains("sessions (0)"))
        #expect(text.contains("none"))
    }

    @Test("Quiet scenes in effect are named")
    func namesQuietScenes() {
        let text = makeReport(quiet: ["screen locked"]).rendered()
        #expect(text.contains("screen locked"))
    }

    @Test("Writing lands a readable file")
    func writesAFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "diagnostics-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try makeReport().write(to: directory)
        #expect(url.pathExtension == "txt")
        let written = try String(contentsOf: url, encoding: .utf8)
        #expect(written.contains("Mitama Island diagnostics"))
    }

    /// Two reports taken while chasing one bug must both survive.
    @Test("A later report does not replace an earlier one")
    func distinctFilenames() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "diagnostics-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try makeReport().write(to: directory)
        var later = makeReport()
        later.generatedAt = Date(timeIntervalSince1970: 1_700_000_060)
        let second = try later.write(to: directory)

        #expect(first != second)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 2)
    }
}
