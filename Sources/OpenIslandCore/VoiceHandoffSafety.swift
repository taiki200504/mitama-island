import Foundation
import Security

/// A spoken request waiting for its receipt. The id and thread are minted once, at recognition, and kept: every resend
/// of the same utterance carries the same pair, so the queue sees one request (P3①).
public struct PendingHandoff: Codable, Equatable, Sendable {
    public let utteranceID: String
    public let thread: String
    public let text: String

    public init(utteranceID: String, thread: String, text: String) {
        self.utteranceID = utteranceID
        self.thread = thread
        self.text = text
    }
}

public final class PendingHandoffStore: @unchecked Sendable {
    private static let key = "mitama.voiceHandoff.pending.v1"
    private static let limit = 20
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func read() -> [PendingHandoff] {
        guard let data = defaults.data(forKey: Self.key), let items = try? JSONDecoder().decode([PendingHandoff].self, from: data) else { return [] }
        return items.filter { VoiceHandoff.isUUIDv4($0.utteranceID) && VoiceHandoff.isUUIDv4($0.thread) }
    }

    private func write(_ items: [PendingHandoff]) { defaults.set(try? JSONEncoder().encode(Array(items.suffix(Self.limit))), forKey: Self.key) }

    public func all() -> [PendingHandoff] { read() }

    /// The pending request for this utterance: the kept one if there is one (same thread), otherwise a new one.
    /// The same id with other text is refused — it is not a new request and must not get a new id.
    public func begin(utteranceID: String, text: String) -> PendingHandoff? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard VoiceHandoff.isUUIDv4(utteranceID), !cleaned.isEmpty else { return nil }
        var items = read()
        if let kept = items.first(where: { $0.utteranceID == utteranceID }) { return kept.text == cleaned ? kept : nil }
        let created = PendingHandoff(utteranceID: utteranceID, thread: UUID().uuidString.lowercased(), text: cleaned)
        items.append(created)
        write(items)
        return created
    }

    /// The receipt was confirmed: it leaves the list.
    public func acknowledge(utteranceID: String) { write(read().filter { $0.utteranceID != utteranceID }) }
}

/// Opens a link only in an app whose bundle id and code signature were checked against a requirement that pins the
/// signer. Anything unchecked gives nil, and the caller falls back to the Hub (a same-scheme impostor gets nothing).
public enum RecipientAppCheck {
    public static func verified(_ candidate: URL?, bundleID: String, requirement text: String?) -> URL? {
        guard let candidate, let text, !text.isEmpty, text.count <= 512,
              text.contains("anchor apple") || text.contains("certificate leaf = H\""), text.contains("identifier \""),
              Bundle(url: candidate)?.bundleIdentifier == bundleID else { return nil }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement else { return nil }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(candidate as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate)
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess ? candidate : nil
    }
}

/// Who rings the meeting-start alert: exactly one of the island, the Mac app and the iPhone app, kept in one place in
/// the database (`mos_owner_settings.meeting_ringer`, written through the owner's RPC). The island has no owner login,
/// so it only reads that row with its own service key; if it cannot read it, it stays quiet.
public enum MeetingAlertOwner: String, Sendable { case island, mac, iphone }

public enum MeetingRinger {
    /// The owner from the PostgREST rows. No row yet means it was never switched, so it is still the island (the
    /// database's default). Anything unreadable or unknown is nil.
    public static func owner(fromRows data: Data) -> MeetingAlertOwner? {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        guard let row = rows.first else { return .island }
        guard let value = row["meeting_ringer"] as? String else { return nil }
        return MeetingAlertOwner(rawValue: value)
    }

    /// A missed alert is better than the same meeting ringing on two devices.
    public static func islandMayRing(_ owner: MeetingAlertOwner?) -> Bool { owner == .island }
}
