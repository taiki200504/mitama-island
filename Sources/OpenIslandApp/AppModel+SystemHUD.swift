import Foundation

extension AppModel {
    /// Wires the HUD coordinator to settings and the overlay it presents its
    /// gauge through. Safe to call from `init`: it touches nothing outside
    /// the app itself. Actually starting the `CGEvent` tap is
    /// `startSystemHUDIfNeeded()`'s job — the same split `configureFocusTimer`
    /// and `startPanelHotkeys` follow, and for the same reason: a global tap
    /// belongs behind the harness guard, plain wiring does not.
    func configureSystemHUD() {
        systemHUD.settings = settings.hud
        systemHUD.overlay = overlay
    }

    /// Starts the `CGEvent` tap if the setting says it should already be
    /// running. Called from `startIfNeeded()`, guarded by
    /// `disablesOverlayEventMonitoringDuringHarness` for the same reason
    /// `startPanelHotkeys()` is: a global event tap installed from a
    /// screenshot process would take these keys away from the copy of the
    /// app someone is actually using.
    func startSystemHUDIfNeeded() {
        guard settings.hud.replacesSystem else { return }
        systemHUD.start()
    }
}
