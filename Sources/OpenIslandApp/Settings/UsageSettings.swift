import Foundation
import Observation
import OpenIslandCore

/// How rate-limit usage is shown, and when it interrupts.
@Observable
final class UsageSettings: PreferenceGroup {
    @ObservationIgnored let registrar = ObservationRegistrar()
    @ObservationIgnored let store: PreferenceStore

    init(store: PreferenceStore = .standard) {
        self.store = store
    }

    var valueMode: UsageValueMode {
        get {
            registrar.access(self, keyPath: \.valueMode)
            let raw = store.value(Keys.valueMode, default: UsageValueMode.used.rawValue)
            return UsageValueMode(rawValue: raw) ?? .used
        }
        set {
            registrar.withMutation(of: self, keyPath: \.valueMode) {
                store.setValue(newValue.rawValue, forKey: Keys.valueMode)
            }
        }
    }

    /// Percentage used at which to raise a card. Zero means never — the default,
    /// because an unasked-for interruption about a quota is exactly the kind of
    /// noise this app is meant to reduce.
    var alertThreshold: Int {
        get { read(\.alertThreshold, Keys.alertThreshold, 0) }
        set { write(\.alertThreshold, Keys.alertThreshold, newValue) }
    }

    /// Show every window with its own countdown, not just the busiest one.
    var showResetCards: Bool {
        get { read(\.showResetCards, Keys.showResetCards, false) }
        set { write(\.showResetCards, Keys.showResetCards, newValue) }
    }

    /// The threshold a switch-on lands on. Chosen so the warning still leaves
    /// room to change course.
    static let suggestedThreshold = 80

    var alertsEnabled: Bool {
        get { alertThreshold > 0 }
        set { alertThreshold = newValue ? Self.suggestedThreshold : 0 }
    }

    enum Defaults {
        /// Below half there is nothing to warn about; above 95 the warning
        /// arrives too late to change what you do.
        static let alertThresholdRange: ClosedRange<Double> = 50...95
    }

    enum Keys {
        static let valueMode = "usage.valueMode"
        static let alertThreshold = "usage.alertThreshold"
        static let showResetCards = "usage.showResetCards"
    }
}
