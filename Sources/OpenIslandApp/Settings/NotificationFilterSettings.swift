import Foundation
import Observation
import OpenIslandCore

/// What part of a session a rule looks at.
enum SilenceRuleField: String, Codable, CaseIterable, Sendable {
    case workingDirectory
    case firstPrompt

    var labelKey: String { "settings.notifications.field.\(rawValue)" }
}

/// How the pattern is compared.
enum SilenceRuleMatch: String, Codable, CaseIterable, Sendable {
    case prefix
    case contains
    case equals

    var labelKey: String { "settings.notifications.match.\(rawValue)" }
}

/// One reason to keep a session off the island.
struct SilenceRule: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var field: SilenceRuleField
    var match: SilenceRuleMatch
    var pattern: String
    /// Presets ship with the app and cannot be edited, only switched off.
    var presetKey: String?

    var isPreset: Bool { presetKey != nil }

    init(
        id: String = UUID().uuidString,
        field: SilenceRuleField,
        match: SilenceRuleMatch,
        pattern: String,
        presetKey: String? = nil
    ) {
        self.id = id
        self.field = field
        self.match = match
        self.pattern = pattern
        self.presetKey = presetKey
    }

    /// Case-insensitive throughout: paths and prompts are typed by hand and a
    /// rule that misses because of capitalisation reads as a broken rule.
    func matches(_ session: AgentSession) -> Bool {
        guard !pattern.isEmpty, let subject = subject(of: session), !subject.isEmpty else {
            return false
        }
        let haystack = subject.lowercased()
        let needle = pattern.lowercased()
        switch match {
        case .prefix:   return haystack.hasPrefix(needle)
        case .contains: return haystack.contains(needle)
        case .equals:   return haystack == needle
        }
    }

    private func subject(of session: AgentSession) -> String? {
        switch field {
        case .workingDirectory:
            session.jumpTarget?.workingDirectory
        case .firstPrompt:
            session.claudeMetadata?.initialUserPrompt
        }
    }
}

extension SilenceRule {
    /// Filters the app ships with, aimed at the background sessions agents spawn
    /// for their own bookkeeping.
    static let presets: [SilenceRule] = [
        SilenceRule(
            id: "preset.claudeMem",
            field: .workingDirectory,
            match: .contains,
            pattern: "/.claude-mem",
            presetKey: "claudeMem"
        ),
        SilenceRule(
            id: "preset.codexMemories",
            field: .workingDirectory,
            match: .contains,
            pattern: "/.codex/memories",
            presetKey: "codexMemories"
        ),
        SilenceRule(
            id: "preset.memoryWritingAgent",
            field: .firstPrompt,
            match: .prefix,
            pattern: "## Memory Writing Agent",
            presetKey: "memoryWritingAgent"
        ),
        SilenceRule(
            id: "preset.titleGenerator",
            field: .firstPrompt,
            match: .contains,
            pattern: "generate a short title",
            presetKey: "titleGenerator"
        ),
    ]

    var presetLabelKey: String { "settings.notifications.preset.\(presetKey ?? "custom")" }
}

/// Which sessions never reach the island.
final class NotificationFilterSettings: PreferenceGroup {
    let registrar = ObservationRegistrar()
    let store: PreferenceStore

    init(store: PreferenceStore = .standard) {
        self.store = store
    }

    /// Called whenever the rule set changes, so whoever caches a filtered view
    /// of the sessions can throw it away.
    ///
    /// Held in a box because the group is `Sendable`, which rules out a mutable
    /// stored property.
    private let changeHandler = ChangeHandlerBox()

    var onRulesChanged: (() -> Void)? {
        get { changeHandler.value }
        set { changeHandler.value = newValue }
    }

    private final class ChangeHandlerBox: @unchecked Sendable {
        private let lock = NSLock()
        private var handler: (() -> Void)?

        var value: (() -> Void)? {
            get { lock.lock(); defer { lock.unlock() }; return handler }
            set { lock.lock(); defer { lock.unlock() }; handler = newValue }
        }
    }

    /// Preset keys in force. All of them start on: the sessions they hide are
    /// an agent's own bookkeeping, which nobody asked to watch.
    var enabledPresets: [String] {
        get { read(\.enabledPresets, Keys.enabledPresets, SilenceRule.presets.compactMap(\.presetKey)) }
        set { write(\.enabledPresets, Keys.enabledPresets, newValue) }
    }

    func isEnabled(_ preset: SilenceRule) -> Bool {
        guard let key = preset.presetKey else { return false }
        return enabledPresets.contains(key)
    }

    func setEnabled(_ enabled: Bool, for preset: SilenceRule) {
        guard let key = preset.presetKey else { return }
        var keys = Set(enabledPresets)
        if enabled { keys.insert(key) } else { keys.remove(key) }
        enabledPresets = SilenceRule.presets
            .compactMap(\.presetKey)
            .filter(keys.contains)
        onRulesChanged?()
    }

    /// Rules the user wrote, stored as JSON because they are a list of records
    /// rather than a scalar.
    var customRules: [SilenceRule] {
        get {
            registrar.access(self, keyPath: \.customRules)
            let raw = store.value(Keys.customRules, default: "")
            guard let data = raw.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([SilenceRule].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            let encoded = (try? JSONEncoder().encode(newValue))
                .flatMap { String(data: $0, encoding: .utf8) } ?? ""
            registrar.withMutation(of: self, keyPath: \.customRules) {
                store.setValue(encoded, forKey: Keys.customRules)
            }
            onRulesChanged?()
        }
    }

    func addRule(_ rule: SilenceRule) {
        guard !rule.pattern.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        customRules.append(rule)
    }

    func removeRule(id: String) {
        customRules.removeAll { $0.id == id }
    }

    /// Every rule currently in force.
    var activeRules: [SilenceRule] {
        SilenceRule.presets.filter(isEnabled) + customRules
    }

    func isSilenced(_ session: AgentSession) -> Bool {
        activeRules.contains { $0.matches(session) }
    }

    /// How many of the given sessions a candidate pattern would hide, for the
    /// live count next to the input field.
    func matchCount(for rule: SilenceRule, in sessions: [AgentSession]) -> Int {
        sessions.filter(rule.matches).count
    }
}

extension NotificationFilterSettings {
    enum Keys {
        static let enabledPresets = "notifications.enabledPresets"
        static let customRules = "notifications.customRules"
    }
}
