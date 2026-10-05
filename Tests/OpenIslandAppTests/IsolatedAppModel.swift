import Foundation
@testable import OpenIslandApp
import OpenIslandCore

@MainActor func isolatedAppModel(
    terminalJumpAction: @escaping @Sendable (JumpTarget) throws -> String = { target in
        try TerminalJumpService().jump(to: target)
    },
    isNotificationSessionAlreadyFrontmost: @escaping @Sendable (AgentSession) async -> Bool = { session in
        await ForegroundTerminalSessionProbe().matches(session: session)
    },
    settings: SettingsStore? = nil,
    // The real Focus database, lock screen and screen-sharing apps on the
    // developer's Mac must not decide whether a test's notification shows.
    quietScenes: QuietSceneMonitor = QuietSceneMonitor(
        assertionsURL: FileManager.default.temporaryDirectory.appendingPathComponent("island-test-no-focus-" + UUID().uuidString + ".json"),
        runningBundleIdentifiers: { [] },
        screenIsLocked: { false }
    ),
    paseoQuestions: PaseoQuestionCoordinator = PaseoQuestionCoordinator(),
    discovery: SessionDiscoveryCoordinator? = nil,
    registryDirectory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("island-test-" + UUID().uuidString)
) -> AppModel {
    let isolatedSettings = settings ?? SettingsStore(store: PreferenceStore(suite: UserDefaults(suiteName: "island-test-" + UUID().uuidString)!))
    let isolatedDiscovery = discovery ?? SessionDiscoveryCoordinator(
        codexSessionStore: CodexSessionStore(fileURL: registryDirectory.appendingPathComponent("codex.json")),
        claudeSessionRegistry: ClaudeSessionRegistry(fileURL: registryDirectory.appendingPathComponent("claude.json")),
        openCodeSessionRegistry: OpenCodeSessionRegistry(fileURL: registryDirectory.appendingPathComponent("opencode.json")),
        cursorSessionRegistry: CursorSessionRegistry(fileURL: registryDirectory.appendingPathComponent("cursor.json")))
    return AppModel(terminalJumpAction: terminalJumpAction,
        isNotificationSessionAlreadyFrontmost: isNotificationSessionAlreadyFrontmost,
        settings: isolatedSettings, quietScenes: quietScenes, paseoQuestions: paseoQuestions, discovery: isolatedDiscovery)
}
