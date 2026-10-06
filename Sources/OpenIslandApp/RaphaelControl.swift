import Foundation
import OpenIslandCore

/// Controls the Raphael desktop companion by calling the `raphaelctl` executable
/// (`~/Developer/Personal/jarvis/companion/raphaelctl`). Calls run on a background queue
/// with a 10s timeout and pass only fixed words in argv.
enum RaphaelControl {
    private static let controlPath = "~/Developer/Personal/jarvis/companion/raphaelctl"
    private static let timeout: TimeInterval = 10

    static func fetchStatus() async -> RaphaelStatus? {
        guard let data = await run(["status"]) else { return nil }
        return RaphaelStatus.parse(from: data)
    }

    static func enable() async { _ = await run(["on"]) }
    static func disable() async { _ = await run(["off"]) }
    static func muteMicrophone() async { _ = await run(["mute", "mic"]) }
    static func unmuteMicrophone() async { _ = await run(["unmute", "mic"]) }
    static func muteVoice() async { _ = await run(["mute", "voice"]) }
    static func unmuteVoice() async { _ = await run(["unmute", "voice"]) }

    private static func run(_ argv: [String]) async -> Data? {
        let path = (controlPath as NSString).expandingTildeInPath
        let limit = timeout
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runBlocking(path: path, argv: argv, timeout: limit))
            }
        }
    }

    private static func runBlocking(path: String, argv: [String], timeout: TimeInterval) -> Data? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = argv
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
