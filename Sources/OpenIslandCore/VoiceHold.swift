import Foundation

/// The state of one hold-to-talk press for a spoken request. Pure, so the rules (one press = one utterance id,
/// a quick tap never opens the microphone, one final delivered once, stale results dropped) are tested without audio.
public struct VoiceHold: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case idle, listening, awaitingFinal }

    /// The longest a press may listen. The microphone is let go by itself at this point.
    public static let maxHold: TimeInterval = 60

    public private(set) var phase: Phase = .idle
    public private(set) var utteranceID: String?
    public private(set) var partialText = ""

    public init() {}

    /// Starts an utterance and returns its id (minted once, here). Nil if one is already running.
    public mutating func press() -> String? {
        guard phase == .idle else { return nil }
        let id = UUID().uuidString.lowercased()
        utteranceID = id
        partialText = ""
        phase = .listening
        return id
    }

    /// Asked when the microphone is ready to open (after the permission prompts). False means the press is over or was
    /// replaced — typically the key was let go before the start ran — so the microphone must not open.
    public mutating func startIfStillHeld(_ id: String) -> Bool {
        guard utteranceID == id else { return false }
        switch phase {
        case .listening: return true
        case .awaitingFinal: reset(); return false
        case .idle: return false
        }
    }

    public func shouldAutoRelease(heldFor seconds: TimeInterval) -> Bool { phase == .listening && seconds >= Self.maxHold }

    public mutating func partial(_ text: String) {
        guard phase != .idle else { return }
        partialText = text
    }

    /// The button was let go: stop listening, wait for the recognizer's final.
    public mutating func release() { if phase == .listening { phase = .awaitingFinal } }

    /// The recognizer's final text. Delivered once; a stale or empty final returns nil.
    public mutating func final(_ text: String) -> (utteranceID: String, text: String)? {
        guard phase != .idle, let id = utteranceID else { return nil }
        reset()
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : (id, cleaned)
    }

    public mutating func cancel() { reset() }

    /// The app lost focus or went away: stop at once and drop whatever comes later. True if something was running.
    @discardableResult
    public mutating func appBackgrounded() -> Bool {
        let wasRunning = phase != .idle
        reset()
        return wasRunning
    }

    private mutating func reset() {
        phase = .idle
        utteranceID = nil
        partialText = ""
    }

    public static func == (lhs: VoiceHold, rhs: VoiceHold) -> Bool {
        lhs.phase == rhs.phase && lhs.utteranceID == rhs.utteranceID && lhs.partialText == rhs.partialText
    }
}

/// Whether the owner has turned on spoken requests. Off until they do (the microphone is never on by default).
public final class VoiceRequestSettings: @unchecked Sendable {
    private static let key = "mitama.voiceRequest.enabled"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var isEnabled: Bool {
        get { defaults.bool(forKey: Self.key) }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}
