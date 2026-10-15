# mitama OS window

`MitamaOSWindowController` owns one retained NSWindow/WKWebView. Closing hides the
window; the default WebKit website data store retains login data across launches.
Window geometry is saved as `mitamaOS.window`.

`UserDefaults` key `mitamaOS.url` overrides the Hub URL. Only HTTPS URLs with a
host and without embedded credentials are accepted. Invalid values use
`https://mitama-os-hub.vercel.app`. Navigation stays embedded only for HTTPS on
the configured host and port. Other HTTP(S), mailto and tel links open in the
default application; executable/local URL schemes are cancelled. Same-host
`target=_blank` navigates the existing web view.

`show(path:)` accepts paths beginning with `/`, rejects network-relative paths,
backslashes and control characters, and falls back to `/`. It replaces the base
URL's path, query and fragment. Notification and external-request entry points
open `/decide`; general entry points open `/`.

## Manual verification

1. Run the current branch's `OpenIslandApp`. Open the status menu: its first item
   should be “mitama OS を開く” in Japanese. Open it, then use the island's window
   icon and Control-Option-M: all three should focus the same window. The global
   shortcut follows the existing keyboard-shortcuts master setting.
2. Sign in, resize and move the window, close it, and reopen. Check login and
   geometry. Quit and relaunch the app and repeat to verify persistence.
3. Click a Hub link to Gmail or マカセタ: the default browser should open. Check a
   same-host target=_blank link stays in the existing Hub window.
4. Click an island notification or the external-request section heading: the
   existing window should navigate to `/decide`.
5. Set `mitamaOS.url` in the app's defaults domain to another HTTPS Hub host and
   reopen. Check its links stay embedded; set an HTTP value and check fallback.
6. Switch between Japanese, English, Simplified and Traditional Chinese. Check
   the status-menu item and header button's accessibility label.

## Changed files

- `Sources/OpenIslandCore/MitamaOSURL.swift`
- `Sources/OpenIslandApp/MitamaOSWindowController.swift`
- `Sources/OpenIslandApp/AppModel.swift`
- `Sources/OpenIslandApp/StatusItemController.swift`
- `Sources/OpenIslandApp/Hotkey/PanelHotkeyCoordinator.swift`
- `Sources/OpenIslandApp/Views/Island/IslandOpenedHeaderView.swift`
- `Sources/OpenIslandApp/Views/Island/IslandPanelView.swift`
- `Sources/OpenIslandApp/Views/Island/IslandSessionListView.swift`
- `Sources/OpenIslandApp/Resources/{ja,en,zh-Hans,zh-Hant}.lproj/Localizable.strings`
- `Tests/OpenIslandCoreTests/MitamaOSURLTests.swift`
- `Tests/OpenIslandAppTests/MitamaOSHotkeyTests.swift`
- `docs/mitama-os-window.md`

## Verification result (2026-10-15)

- `swift build`: passed on the final source.
- `swift test --filter MitamaOS`: passed, 9 tests (8 Core + 1 app hotkey;
  25 cases including parameterized inputs).
- Both commands needed `--disable-sandbox --cache-path /tmp/mitama-os-swiftpm-cache`
  and `CLANG_MODULE_CACHE_PATH=/tmp/mitama-os-module-cache`
  / `SWIFTPM_MODULECACHE_OVERRIDE=/tmp/mitama-os-module-cache` in this restricted
  execution environment. Final logs: `/tmp/mitama-os-final-build.log` and
  `/tmp/mitama-os-final-test.log`.
- Build started only after the one-minute load average fell to 8 or below;
  build and test ran sequentially. Existing unrelated compiler warnings remain.
- `git diff --check`: passed.
- Interactive window/login/navigation checks were not performed.
- No commit created; the parent owns the commit.
