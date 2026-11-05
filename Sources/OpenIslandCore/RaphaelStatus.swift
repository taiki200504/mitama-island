import Foundation

/// The status of the Raphael desktop companion.
/// Decoded from `raphaelctl status` JSON output.
public struct RaphaelStatus: Sendable, Codable, Equatable {
    /// Whether Raphael is enabled (started by the user).
    public let enabled: Bool
    /// Whether the Raphael process is currently running.
    public let running: Bool
    /// Whether the microphone input is active (`false` = muted).
    public let mic: Bool
    /// Whether the voice output is active (`false` = muted).
    public let voice: Bool
    /// 島から on/off を出してよいか。`raphaelctl` の出力ではなく、登録済みの常駐（`RaphaelTarget`）から決める。
    public var canSwitchOnOff: Bool = true

    private enum CodingKeys: String, CodingKey { case enabled, running, mic, voice }

    public init(enabled: Bool, running: Bool, mic: Bool, voice: Bool, canSwitchOnOff: Bool = true) {
        self.enabled = enabled
        self.running = running
        self.mic = mic
        self.voice = voice
        self.canSwitchOnOff = canSwitchOnOff
    }

    /// 操作先に合わせた表示用の状態。旧アプリ以外は、動いていると確かめられない限り「表示中」にしない。
    public func presented(for target: RaphaelTarget) -> RaphaelStatus {
        guard !target.allowsOnOff else { return self }
        return RaphaelStatus(enabled: enabled && running, running: running, mic: mic, voice: voice, canSwitchOnOff: false)
    }

    /// Parse JSON status from `raphaelctl status` output.
    /// - Parameter data: The raw JSON data from raphaelctl's stdout.
    /// - Returns: Parsed status, or nil if parsing fails.
    public static func parse(from data: Data) -> RaphaelStatus? {
        let decoder = JSONDecoder()
        return try? decoder.decode(RaphaelStatus.self, from: data)
    }
}
