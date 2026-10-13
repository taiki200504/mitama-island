import Foundation
import Testing
@testable import OpenIslandApp

struct EarshotDeviceReporterTests {
    @Test func newerCommandsApplyBothSwitchValues() {
        for enabled in [true, false] {
            let command = EarshotRemoteCommand(listen_command: enabled, command_at: "2026-10-13T01:00:00.123456+00:00")
            let result = command.applicable(after: 0)
            #expect(result?.enabled == enabled)
            #expect((result?.at ?? 0) > 0)
        }
    }

    @Test func replayAndOlderCommandsDoNotOverrideLocalSwitch() {
        let command = EarshotRemoteCommand(listen_command: false, command_at: "2026-10-13T01:00:00Z")
        let saved = command.applicable(after: 0)!.at
        #expect(command.applicable(after: saved) == nil)
        #expect(command.applicable(after: saved + 1) == nil)
    }

    @Test func subMillisecondCommandsRemainOrdered() {
        let previous = EarshotRemoteCommand(listen_command: false, command_at: "2026-10-13T01:00:00.123456Z")
        let next = EarshotRemoteCommand(listen_command: true, command_at: "2026-10-13T01:00:00.123789Z")
        let saved = previous.applicable(after: 0)!.at
        #expect(next.applicable(after: saved)?.enabled == true)
    }

    @Test func missingOrMalformedCommandsAreIgnored() {
        #expect(EarshotRemoteCommand(listen_command: nil, command_at: "2026-10-13T01:00:00Z").applicable(after: 0) == nil)
        #expect(EarshotRemoteCommand(listen_command: true, command_at: nil).applicable(after: 0) == nil)
        #expect(EarshotRemoteCommand(listen_command: true, command_at: "invalid").applicable(after: 0) == nil)
    }

    @Test @MainActor func reportNeverContainsHubCommandColumns() {
        let settings = AmbientListenSettings(store: PreferenceStore(suite: UserDefaults(suiteName: UUID().uuidString)!))
        let reporter = EarshotDeviceReporter(session: AmbientListenSession(settings: settings), settings: settings)
        let body = reporter.statusBody(deviceID: "test")
        #expect(body["listen_command"] == nil)
        #expect(body["command_at"] == nil)
        #expect(body["phase"] as? String == "off")
        #expect(body["kind"] as? String == "mac")
    }

    @Test @MainActor func pendingFilesExcludeDoneMarkers() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["pending.wav", "complete.wav", "complete.wav.done", "other.txt"] {
            try Data().write(to: directory.appendingPathComponent(name))
        }
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("directory.wav"), withIntermediateDirectories: true)
        #expect(EarshotDeviceReporter.pendingFiles(in: directory) == 1)
        #expect(EarshotDeviceReporter.pendingFiles(in: directory.appendingPathComponent("missing")) == 0)
    }
}
