import Foundation
import Testing
@testable import OpenIslandApp

@Suite struct ClaudeProcessRegistryTests {
    @Test func listsOnlySessionsWhoseProcessIsRunning() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data(#"{"pid":101,"sessionId":"idle-paseo","kind":"interactive"}"#.utf8)
            .write(to: directory.appendingPathComponent("101.json"))
        try Data(#"{"pid":102,"sessionId":"crashed"}"#.utf8)
            .write(to: directory.appendingPathComponent("102.json"))
        try Data("not json".utf8).write(to: directory.appendingPathComponent("103.json"))
        try Data(#"{"pid":104,"sessionId":"not-a-registry-file"}"#.utf8)
            .write(to: directory.appendingPathComponent("104.key"))

        let ids = ProcessMonitoringCoordinator.liveClaudeSessionIDs(
            registryDirectory: directory,
            isProcessRunning: { $0 == 101 || $0 == 104 }
        )

        #expect(ids == ["idle-paseo"])
    }

    @Test func missingRegistryMeansNoSessions() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        #expect(ProcessMonitoringCoordinator.liveClaudeSessionIDs(registryDirectory: directory, isProcessRunning: { _ in true }).isEmpty)
    }
}
