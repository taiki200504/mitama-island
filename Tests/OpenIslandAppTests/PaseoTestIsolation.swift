import Foundation
@testable import OpenIslandApp
import OpenIslandCore

@MainActor func isolatedPaseoAppModel(
    _ coordinator: PaseoQuestionCoordinator,
    settings: SettingsStore? = nil,
    registryDirectory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("paseo-test-" + UUID().uuidString)
) -> AppModel {
    let isolatedSettings = settings ?? SettingsStore(store: PreferenceStore(suite: UserDefaults(suiteName: "paseo-test-" + UUID().uuidString)!))
    let discovery = SessionDiscoveryCoordinator(
        codexSessionStore: CodexSessionStore(fileURL: registryDirectory.appendingPathComponent("codex.json")),
        claudeSessionRegistry: ClaudeSessionRegistry(fileURL: registryDirectory.appendingPathComponent("claude.json")),
        openCodeSessionRegistry: OpenCodeSessionRegistry(fileURL: registryDirectory.appendingPathComponent("opencode.json")),
        cursorSessionRegistry: CursorSessionRegistry(fileURL: registryDirectory.appendingPathComponent("cursor.json")))
    return AppModel(settings: isolatedSettings, paseoQuestions: coordinator, discovery: discovery)
}
