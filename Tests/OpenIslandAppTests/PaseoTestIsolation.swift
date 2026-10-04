import Foundation
@testable import OpenIslandApp
import OpenIslandCore

@MainActor func isolatedPaseoAppModel(
    _ coordinator: PaseoQuestionCoordinator,
    settings: SettingsStore? = nil,
    registryDirectory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("paseo-test-" + UUID().uuidString)
) -> AppModel {
    isolatedAppModel(settings: settings, paseoQuestions: coordinator, registryDirectory: registryDirectory)
}
