import Foundation

/// Tri-state record of whether the user wants a given agent's hooks installed.
///
/// `untouched` is the default for a never-seen agent. Once the user makes a
/// decision — in onboarding or settings — the value becomes either
/// `installed` or `uninstalled`. The startup flow must honour `uninstalled`
/// and never silently reinstall.
public enum AgentHookIntent: String, Codable, Sendable, CaseIterable {
    case untouched
    case installed
    case uninstalled
}

/// Canonical identifier for every agent whose hooks Open Island manages.
///
/// Raw values are stable on-disk keys (used in UserDefaults); do not rename
/// existing cases without a migration.
public enum AgentIdentifier: String, Codable, Sendable, CaseIterable {
    case claudeCode
    case codex
    case cursor
    case qoder
    case qwenCode
    case factory
    case codebuddy
    case openCode
    case gemini
    case kimi
    case claudeUsageBridge

    /// The name a person would recognise, for anything user-facing.
    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .qoder: "Qoder"
        case .qwenCode: "Qwen Code"
        case .factory: "Factory"
        case .codebuddy: "CodeBuddy"
        case .openCode: "OpenCode"
        case .gemini: "Gemini CLI"
        case .kimi: "Kimi CLI"
        case .claudeUsageBridge: "Claude Usage Bridge"
        }
    }
}
