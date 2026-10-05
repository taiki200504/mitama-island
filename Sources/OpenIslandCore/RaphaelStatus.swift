import Foundation

/// The status of the Raphael desktop companion.
/// Decoded from `raphaelctl status` JSON output.
public struct RaphaelStatus: Sendable, Codable, Equatable {
    /// Whether Raphael is enabled (started by the user).
    public let enabled: Bool
    /// Whether the Raphael process is currently running.
    public let running: Bool
    /// Whether the microphone input is muted.
    public let mic: Bool
    /// Whether the voice output is muted.
    public let voice: Bool

    public init(enabled: Bool, running: Bool, mic: Bool, voice: Bool) {
        self.enabled = enabled
        self.running = running
        self.mic = mic
        self.voice = voice
    }

    /// Parse JSON status from `raphaelctl status` output.
    /// - Parameter data: The raw JSON data from raphaelctl's stdout.
    /// - Returns: Parsed status, or nil if parsing fails.
    public static func parse(from data: Data) -> RaphaelStatus? {
        let decoder = JSONDecoder()
        return try? decoder.decode(RaphaelStatus.self, from: data)
    }
}
