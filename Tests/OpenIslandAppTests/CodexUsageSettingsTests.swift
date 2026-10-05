import Foundation
import Testing
@testable import OpenIslandApp

@MainActor
@Suite(.serialized)
struct CodexUsageSettingsTests {
    @Test
    func usageToggleStartsStopsAndRestartsMonitoring() {
        let defaults = UserDefaults.standard
        let key = "app.showCodexUsage"
        let previous = defaults.object(forKey: key)
        defaults.set(false, forKey: key)
        defer {
            if let previous { defaults.set(previous, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        let model = isolatedAppModel()
        defer { model.hooks.stopCodexUsageMonitoring() }

        #expect(!model.hooks.isCodexUsageMonitoring)
        model.showCodexUsage = true
        #expect(model.hooks.isCodexUsageMonitoring)
        #expect(defaults.bool(forKey: key))
        model.showCodexUsage = false
        #expect(!model.hooks.isCodexUsageMonitoring)
        #expect(model.hooks.codexUsageSnapshot == nil)
        model.showCodexUsage = true
        #expect(model.hooks.isCodexUsageMonitoring)
    }
}
