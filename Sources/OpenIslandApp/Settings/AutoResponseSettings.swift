import Foundation
import Observation
import OpenIslandCore

/// What the island answers on the user's behalf.
///
/// There is deliberately no deny: refusing an agent is a judgement about the
/// specific thing it asked for, and a standing rule cannot make that judgement.
enum AutoResponseBehavior: String, Codable, CaseIterable, Sendable {
    /// Approve this one request, ask again next time.
    case allowOnce
    /// Auto-accept edits for the rest of the session, keep asking about the rest.
    case acceptEdits
    /// Stop asking for the rest of the session.
    case bypassPermissions

    var labelKey: String { "settings.autoResponse.behavior.\(rawValue)" }

    /// The mode this behaviour puts the session into, if any.
    var permissionMode: ClaudePermissionMode? {
        switch self {
        case .allowOnce:         nil
        case .acceptEdits:       .acceptEdits
        case .bypassPermissions: .bypassPermissions
        }
    }
}

/// One place the user has decided not to be asked about.
///
/// Matching is delegated to `SilenceRule` rather than reimplemented: two copies
/// of "does this session match" would drift, and the island would then hide and
/// auto-answer different sets of sessions.
struct AutoResponseRule: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var field: SilenceRuleField
    var match: SilenceRuleMatch
    var pattern: String
    var behavior: AutoResponseBehavior

    init(
        id: String = UUID().uuidString,
        field: SilenceRuleField,
        match: SilenceRuleMatch,
        pattern: String,
        behavior: AutoResponseBehavior
    ) {
        self.id = id
        self.field = field
        self.match = match
        self.pattern = pattern
        self.behavior = behavior
    }

    func matches(_ session: AgentSession) -> Bool {
        SilenceRule(field: field, match: match, pattern: pattern).matches(session)
    }
}

/// Which permission requests the island answers without asking.
///
/// Off until the user writes a rule. Approving on someone's behalf is the one
/// thing the island does that they cannot take back, so it never happens by
/// default and every rule is one they typed.
final class AutoResponseSettings: PreferenceGroup {
    let registrar = ObservationRegistrar()
    let store: PreferenceStore

    init(store: PreferenceStore = .standard) {
        self.store = store
    }

    /// A single switch that stops every rule at once. A rule firing on the wrong
    /// session is found mid-work, when hunting for which of several rules did it
    /// is exactly the wrong task to be handed.
    var isEnabled: Bool {
        get { read(\.isEnabled, Keys.enabled, true) }
        set { write(\.isEnabled, Keys.enabled, newValue) }
    }

    var rules: [AutoResponseRule] {
        get {
            registrar.access(self, keyPath: \.rules)
            let raw = store.value(Keys.rules, default: "")
            guard let data = raw.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([AutoResponseRule].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            let encoded = (try? JSONEncoder().encode(newValue))
                .flatMap { String(data: $0, encoding: .utf8) } ?? ""
            registrar.withMutation(of: self, keyPath: \.rules) {
                store.setValue(encoded, forKey: Keys.rules)
            }
        }
    }

    func addRule(_ rule: AutoResponseRule) {
        guard !rule.pattern.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard !rules.contains(where: {
            $0.field == rule.field && $0.match == rule.match
                && $0.pattern.caseInsensitiveCompare(rule.pattern) == .orderedSame
        }) else { return }
        rules.append(rule)
    }

    func removeRule(id: String) {
        rules.removeAll { $0.id == id }
    }

    /// The rule that answers this session, or nil to leave it to the user.
    ///
    /// First match wins, so a narrower rule written later cannot override an
    /// earlier broad one — the list order the user sees is the order that runs.
    func rule(for session: AgentSession) -> AutoResponseRule? {
        guard isEnabled else { return nil }
        return rules.first { $0.matches(session) }
    }
}

extension AutoResponseSettings {
    enum Keys {
        static let enabled = "autoResponse.enabled"
        static let rules = "autoResponse.rules"
    }
}
