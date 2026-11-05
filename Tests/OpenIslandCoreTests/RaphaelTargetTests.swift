import Foundation
import Testing
@testable import OpenIslandCore

struct RaphaelTargetTests {
    private let home = "/Users/someone"

    private func plist(_ program: String, env: [String: Any]? = nil, label: String = RaphaelTarget.label) throws -> Data {
        var dict: [String: Any] = ["Label": label, "ProgramArguments": [program], "RunAtLoad": true]
        if let env { dict["EnvironmentVariables"] = env }
        return try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    private var legacyExe: String { "\(home)/Applications/Raphael.app/Contents/MacOS/Raphael" }
    private var newExe: String { "\(home)/Applications/Raphael-mitama-os.app/Contents/MacOS/Raphael" }

    @Test("No LaunchAgent and no mitama-os app: unchanged legacy behaviour")
    func legacyWithoutAgent() {
        #expect(RaphaelTarget.resolve(plist: nil, mitamaOSAppInstalled: false, home: home) == .legacy)
    }

    @Test("Old app registered: legacy, on/off allowed")
    func legacyAgent() throws {
        let target = RaphaelTarget.resolve(plist: try plist(legacyExe), mitamaOSAppInstalled: true, home: home)
        #expect(target == .legacy)
        #expect(target.allowsOnOff)
        #expect(target.environmentOverrides.isEmpty)
    }

    @Test("mitama-os app registered: its port, no on/off")
    func mitamaOSAgent() throws {
        let target = RaphaelTarget.resolve(
            plist: try plist(newExe, env: ["PATH": "/usr/bin", "COMPANION_PORT": "8771"]),
            mitamaOSAppInstalled: true, home: home)
        #expect(target == .mitamaOS(port: 8771))
        #expect(!target.allowsOnOff)
        #expect(target.environmentOverrides == ["COMPANION_PORT": "8771"])
        let noPort = RaphaelTarget.resolve(plist: try plist(newExe), mitamaOSAppInstalled: true, home: home)
        #expect(noPort == .mitamaOS(port: 8770))
    }

    @Test("mitama-os app present but not registered, or anything unknown: no on/off")
    func unmanaged() throws {
        #expect(RaphaelTarget.resolve(plist: nil, mitamaOSAppInstalled: true, home: home) == .unmanaged)
        let cases: [Data] = [
            Data("not a plist".utf8),
            try plist("/tmp/evil; rm -rf ~"),
            try plist(newExe, label: "com.example.other"),
            try plist(newExe, env: ["COMPANION_PORT": "80"]),
            try plist(newExe, env: ["COMPANION_PORT": "8771; echo"]),
            try plist(newExe, env: ["COMPANION_PORT": "99999"]),
            try plist(newExe, env: ["COMPANION_PORT": 8771]),
        ]
        for data in cases {
            let target = RaphaelTarget.resolve(plist: data, mitamaOSAppInstalled: false, home: home)
            #expect(target == .unmanaged)
            #expect(!target.allowsOnOff)
            #expect(target.environmentOverrides.isEmpty)
        }
    }

    @Test("Non-legacy status is shown enabled only while it is really running")
    func presentedStatus() {
        let enabledNotRunning = RaphaelStatus(enabled: true, running: false, mic: true, voice: true)
        #expect(enabledNotRunning.presented(for: .legacy) == enabledNotRunning)
        let shown = enabledNotRunning.presented(for: .mitamaOS(port: 8771))
        #expect(!shown.enabled)
        #expect(!shown.canSwitchOnOff)
        let running = RaphaelStatus(enabled: true, running: true, mic: true, voice: true).presented(for: .unmanaged)
        #expect(running.enabled)
        #expect(!running.canSwitchOnOff)
    }
}
