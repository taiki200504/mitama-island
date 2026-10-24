import Foundation
import OpenIslandCore

/// Controls the Raphael desktop companion by calling the `raphaelctl` executable
/// (`~/Developer/Personal/jarvis/companion/raphaelctl`). Calls run on a background queue
/// with a 10s timeout and pass only fixed words in argv.
///
/// 操作先は登録済みの LaunchAgent から毎回決める（`RaphaelTarget`）。mitama-os 版が動いている時は
/// ミュートの知らせをそのポートへ向け、旧アプリへ書き戻す on/off は出さない。
enum RaphaelControl {
    private static let controlPath = "~/Developer/Personal/jarvis/companion/raphaelctl"
    private static let timeout: TimeInterval = 10

    static func fetchStatus() async -> RaphaelStatus? {
        let target = currentTarget()
        guard let data = await run(["status"], target: target) else { return nil }
        return RaphaelStatus.parse(from: data)?.presented(for: target)
    }

    static func enable() async { await runOnOff("on") }
    static func disable() async { await runOnOff("off") }

    private static func runOnOff(_ word: String) async {
        let target = currentTarget()
        guard target.allowsOnOff else { return }
        _ = await run([word], target: target)
    }

    static func currentTarget() -> RaphaelTarget {
        let home = NSHomeDirectory()
        let plistURL = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/LaunchAgents/\(RaphaelTarget.label).plist")
        let appPath = (home as NSString).appendingPathComponent("Applications/Raphael-mitama-os.app")
        return RaphaelTarget.resolve(
            plist: try? Data(contentsOf: plistURL),
            mitamaOSAppInstalled: FileManager.default.fileExists(atPath: appPath),
            home: home
        )
    }

    static func muteMicrophone() async { _ = await run(["mute", "mic"], target: currentTarget()) }
    static func unmuteMicrophone() async { _ = await run(["unmute", "mic"], target: currentTarget()) }
    static func muteVoice() async { _ = await run(["mute", "voice"], target: currentTarget()) }
    static func unmuteVoice() async { _ = await run(["unmute", "voice"], target: currentTarget()) }

    private static func run(_ argv: [String], target: RaphaelTarget) async -> Data? {
        let path = (controlPath as NSString).expandingTildeInPath
        let limit = timeout
        let overrides = target.environmentOverrides
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runBlocking(path: path, argv: argv, overrides: overrides, timeout: limit))
            }
        }
    }

    private static func runBlocking(path: String, argv: [String], overrides: [String: String], timeout: TimeInterval) -> Data? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = argv
        if !overrides.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(overrides) { _, new in new }
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        return pipe.fileHandleForReading.readDataToEndOfFile()
    }
}
