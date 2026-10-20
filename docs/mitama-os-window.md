# mitama OS window

`MitamaOSWindowController` owns one retained NSWindow/WKWebView. Closing hides the
window; the default WebKit website data store retains login data across launches.
Window geometry is saved as `mitamaOS.window`.

`UserDefaults` key `mitamaOS.url` overrides the Hub URL. Only HTTPS URLs with a
host and without embedded credentials are accepted. Invalid values use
`https://mitama-os-hub.vercel.app`. Navigation stays embedded for HTTPS on the configured host and port, the exact
hosts `accounts.google.com` and `accounts.youtube.com`, and subdomains of
`supabase.co` under `/auth/v1/`. Authentication hosts accept only the default
HTTPS port (or explicit 443). Other Google hosts and Supabase paths remain
external. URLs with embedded credentials are cancelled. Other HTTP(S), mailto
and tel links open in the default application; executable/local URL schemes are
cancelled. Allowed `target=_blank` links navigate the existing web view.

The web view uses the fixed Safari 17.6 user agent. This assists compatibility;
Google may still reject embedded authentication, so actual sign-in needs manual
verification. Showing the OS window sets the app activation policy to `.regular`
(Dock and Cmd+Tab); closing hides it and restores `.accessory`. Existing island
windows are retained, and opening still activates the app.

The opened island header has a recording button: “録音” when disabled and a red
dot with “録音中” when enabled. It toggles the same ambient-listening setting and
notifies the same earshot controller as the status menu. Its state label is
localized in all four languages and exposed to accessibility.

`show(path:)` accepts paths beginning with `/`, rejects network-relative paths,
backslashes and control characters, and falls back to `/`. It replaces the base
URL's path, query and fragment. Notification and external-request entry points
open `/decide`; general entry points open `/`.

## Manual verification

1. Run the current branch's `OpenIslandApp`. Open the status menu: its first item
   should be “mitama OS を開く” in Japanese. Open it, then use the island's window
   icon and Control-Option-M: all three should focus the same window. The global
   shortcut follows the existing keyboard-shortcuts master setting.
2. Use Google sign-in and check that Google and Supabase authentication remain
   inside the window and return to a signed-in Hub. Sign in, resize and move the window, close it, and reopen. Check login and
   geometry. Quit and relaunch the app and repeat to verify persistence.
3. Click a Hub link to Gmail or マカセタ: the default browser should open. Check a
   same-host target=_blank link stays in the existing Hub window.
4. Click an island notification or the external-request section heading: the
   existing window should navigate to `/decide`.
5. Set `mitamaOS.url` in the app's defaults domain to another HTTPS Hub host and
   reopen. Check its links stay embedded; set an HTTP value and check fallback.
6. Check Dock and Cmd+Tab while the OS window is open, then close it and check
   that the app returns to accessory mode and the island still works. Reopen it.
7. Toggle recording from the header and status menu; check both reflect the same
   setting, the red dot and recording label, and that the header fits.
8. Switch between Japanese, English, Simplified and Traditional Chinese. Check
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

## Verification result (2026-10-15, authentication / Dock / recording)

- Localization harness lint: passed (5 checks; 882 matching keys in 4 locales).
- Documentation index check: passed.
- `swift build`: unverified; the manifest sandbox failed with
  `sandbox-exec: sandbox_apply: Operation not permitted` (load 7.41 before build).
  Per task instructions, no sandbox bypass or retry was attempted.
- Targeted and full Swift tests: not run after the sandbox failure. Two new
  parameterized Swift Testing tests cover 17 authentication URL inputs.
- `git diff --check`: passed.
- Interactive Google login, Dock/Cmd+Tab and recording checks are not performed.
- No commit created; the parent owns the commit.
