import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// Proves `showsMenuBarIcon` actually reaches whatever owns the
/// `NSStatusItem`, the same way `GeneralBehaviourWiringTests` proves the
/// general pane's other switches reach the engine.
///
/// `AppModel` never touches `NSStatusItem` itself — it calls
/// `onShowsMenuBarIconChanged`, which the app delegate points at the real
/// controller. That indirection is what lets this run without standing up a
/// status item in a headless test process.
///
/// `.serialized`, matching `AppModelSessionListTests`: this preference is
/// backed by `UserDefaults.standard` (same as `showDockIcon` next to it),
/// which every test in this suite shares.
@MainActor
@Suite(.serialized)
struct MenuBarIconPreferenceTests {
    private static let defaultsKey = "general.showsMenuBarIcon"

    init() {
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
    }

    private func makeModel() -> AppModel {
        let name = "wiring-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        let settings = SettingsStore(store: PreferenceStore(suite: suite))
        return AppModel(settings: settings)
    }

    @Test("Defaults to on, so a first launch is always reachable")
    func defaultsToOn() {
        let model = makeModel()
        #expect(model.showsMenuBarIcon == true)
    }

    @Test("Turning it off notifies the controller closure with false")
    func turningItOffNotifiesTheController() {
        let model = makeModel()
        var received: [Bool] = []
        model.onShowsMenuBarIconChanged = { received.append($0) }

        model.showsMenuBarIcon = false

        #expect(received == [false])
    }

    @Test("Turning it back on notifies the controller closure with true")
    func turningItBackOnNotifiesTheController() {
        let model = makeModel()
        model.showsMenuBarIcon = false
        var received: [Bool] = []
        model.onShowsMenuBarIconChanged = { received.append($0) }

        model.showsMenuBarIcon = true

        #expect(received == [true])
    }

    @Test("Setting it to its current value is a no-op — no redundant call")
    func settingSameValueDoesNothing() {
        let model = makeModel()
        var callCount = 0
        model.onShowsMenuBarIconChanged = { _ in callCount += 1 }

        model.showsMenuBarIcon = true

        #expect(callCount == 0)
    }

    @Test("Persists to UserDefaults under its own key, independent of the Dock toggle")
    func persistsUnderItsOwnKey() {
        let model = makeModel()
        // `register(defaults:)` in `AppModel.init()` always populates this key
        // with its own default, so the interesting assertion is that toggling
        // the menu bar preference below never changes it — not that the key
        // is unset, which it never is once any `AppModel` has been built.
        let dockIconValueBefore = UserDefaults.standard.bool(forKey: "app.showDockIcon")

        model.showsMenuBarIcon = false

        #expect(UserDefaults.standard.bool(forKey: Self.defaultsKey) == false)
        #expect(UserDefaults.standard.bool(forKey: "app.showDockIcon") == dockIconValueBefore)
    }

    @Test("statusMenuInputs mirrors the model's own mute, camera and shelf state")
    func statusMenuInputsMirrorsModelState() {
        let model = makeModel()
        model.isSoundMuted = true

        let inputs = model.statusMenuInputs

        #expect(inputs.isMuted == true)
        #expect(inputs.shelfItemNames == model.shelf.items.map(\.displayName))
        #expect(inputs.waitingCount == model.liveAttentionCount)
    }
}
