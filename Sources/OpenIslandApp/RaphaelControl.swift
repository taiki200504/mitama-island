import Foundation
import OpenIslandCore

/// Controls the Raphael desktop companion by calling the raphaelctl executable.
/// All operations run off the main thread to avoid blocking the UI.
@MainActor
final class RaphaelControl {
    private static let controlBinaryPath = "~/Developer/Personal/jarvis/companion/raphaelctl"
    private static let statusTimeout: TimeInterval = 10

    /// Fetch the current status of Raphael.
    /// - Returns: Parsed status, or nil if the binary is unavailable, times out, or parsing fails.
    static func fetchStatus() async -> RaphaelStatus? {
        await performCommand(["status"])
    }

    /// Enable (start) Raphael.
    static func enable() async {
        _ = await performCommand(["on"])
    }

    /// Disable (stop) Raphael.
    static func disable() async {
        _ = await performCommand(["off"])
    }

    /// Mute the microphone input.
    static func muteMicrophone() async {
        _ = await performCommand(["mute", "mic"])
    }

    /// Unmute the microphone input.
    static func unmuteMicrophone() async {
        _ = await performCommand(["unmute", "mic"])
    }

    /// Mute the voice output.
    static func muteVoice() async {
        _ = await performCommand(["mute", "voice"])
    }

    /// Unmute the voice output.
    static func unmuteVoice() async {
        _ = await performCommand(["unmute", "voice"])
    }

    // MARK: - Private

    /// Run the raphaelctl command and return the stdout data.
    /// Only pass safe, fixed strings in argv; never include user input.
    private static func performCommand(_ argv: [String]) async -> Data? {
        return await Task.detached(priority: .userInitiated) {
            let expandedPath = (controlBinaryPath as NSString).expandingTildeInPath
            let fileManager = FileManager.default

            guard fileManager.fileExists(atPath: expandedPath),
                  fileManager.isExecutableFile(atPath: expandedPath) else {
                return nil
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: expandedPath)
            process.arguments = argv

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()

                let semaphore = DispatchSemaphore(value: 0)
                var timedOut = false

                DispatchQueue.global().asyncAfter(deadline: .now() + statusTimeout) {
                    if process.isRunning {
                        process.terminate()
                        timedOut = true
                    }
                    semaphore.signal()
                }

                process.waitUntilExit()
                semaphore.signal()

                guard !timedOut, process.terminationStatus == 0 else {
                    return nil
                }

                return pipe.fileHandleForReading.readDataToEndOfFile()
            } catch {
                return nil
            }
        }.value
    }
}
