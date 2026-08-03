import Foundation
import Observation

/// A group of related, defaults-backed settings.
///
/// Conformers hand-write `Observable` rather than using the `@Observable` macro:
/// the macro only tracks *stored* properties, and property wrappers are rejected
/// outright, so a defaults-backed setting has to be a computed property that
/// drives observation itself. `read`/`write` below are that plumbing.
///
///     final class BehaviourSettings: PreferenceGroup {
///         let registrar = ObservationRegistrar()
///         let store: PreferenceStore
///         init(store: PreferenceStore = .standard) { self.store = store }
///
///         var expandOnHover: Bool {
///             get { read(\.expandOnHover, Keys.expandOnHover, true) }
///             set { write(\.expandOnHover, Keys.expandOnHover, newValue) }
///         }
///     }
///
/// The default value lives next to the property it belongs to, and there is no
/// second copy of the value to keep in sync.
protocol PreferenceGroup: Observable, Sendable, AnyObject {
    var registrar: ObservationRegistrar { get }
    var store: PreferenceStore { get }
}

extension PreferenceGroup {
    func read<T: PreferenceRepresentable>(
        _ keyPath: KeyPath<Self, T>,
        _ key: String,
        _ fallback: T
    ) -> T {
        registrar.access(self, keyPath: keyPath)
        return store.value(key, default: fallback)
    }

    func write<T: PreferenceRepresentable>(
        _ keyPath: KeyPath<Self, T>,
        _ key: String,
        _ value: T
    ) {
        registrar.withMutation(of: self, keyPath: keyPath) {
            store.setValue(value, forKey: key)
        }
    }

    /// Drops the stored value so the property falls back to its declared default.
    func reset<T: PreferenceRepresentable>(_ keyPath: KeyPath<Self, T>, _ key: String) {
        registrar.withMutation(of: self, keyPath: keyPath) {
            store.removeValue(forKey: key)
        }
    }

    func isCustomised(_ key: String) -> Bool {
        store.hasValue(forKey: key)
    }
}
