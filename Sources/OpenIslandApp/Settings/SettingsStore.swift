import Foundation

/// Root holder for every defaults-backed settings group.
///
/// `AppModel` stays responsible for live runtime state — sessions, hooks, the
/// overlay. Anything the user configures and expects to survive a relaunch lives
/// here instead, so neither file has to grow to hold both.
///
/// Not observable itself: each group observes independently, so a view that reads
/// display settings is not invalidated when a behaviour setting changes.
///
/// Groups are added as their settings pane lands, not in advance.
final class SettingsStore: Sendable {
    static let shared = SettingsStore()

    let behaviour: BehaviourSettings
    let display: DisplaySettings
    let shortcuts: ShortcutSettings
    let sound: SoundSettings
    let notificationFilters: NotificationFilterSettings

    init(store: PreferenceStore = .standard) {
        behaviour = BehaviourSettings(store: store)
        display = DisplaySettings(store: store)
        shortcuts = ShortcutSettings(store: store)
        sound = SoundSettings(store: store)
        notificationFilters = NotificationFilterSettings(store: store)
    }
}
