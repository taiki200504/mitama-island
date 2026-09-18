# Packaging

This repository can now produce a local macOS app bundle from the Swift package without requiring an Xcode project archive.

## Current Shape

- `zsh scripts/package-app.sh` builds `OpenIslandApp`, `OpenIslandHooks`, and `OpenIslandSetup` in release mode.
- The script creates `output/package/Open Island.app`.
- The bundle embeds helper binaries inside `Contents/Helpers/` so the app can still locate `OpenIslandHooks` after it leaves the repository checkout.
- The script also creates `output/package/Open Island.zip` for local sharing or later notarization.

## Unsigned First

If the machine does not yet have a `Developer ID Application` certificate, the script still works. It produces an unsigned `.app` bundle and `.zip` archive for local inspection.

Check whether signing identities are available with:

```bash
security find-identity -v -p codesigning
```

If that command reports `0 valid identities found`, packaging is limited to unsigned output until the certificate is created in the Apple Developer account and imported into the login keychain.

### "Open Island is damaged and can't be opened"

This Gatekeeper error appears when macOS quarantines an unsigned or un-notarized download. There are two workarounds:

**Option 1 — remove quarantine (internal/dev use only):**

```bash
xattr -dr com.apple.quarantine "/Applications/Open Island.app"
```

Or right-click the app → **Open** → click **Open** to bypass the block once.

**Option 2 — sign and notarize (required for external distribution):** follow the section below.

## Signing And Notarization

When a signing identity is available, pass it in with environment variables:

```bash
OPEN_ISLAND_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
zsh scripts/package-app.sh
```

The script signs the helper binaries and app bundle, then also signs the DMG itself (required for notarization). Entitlements are declared in `config/packaging/OpenIslandApp.entitlements`.

If a `notarytool` keychain profile is already stored, the same script notarizes and staples in the correct order (app bundle first so the stapled bundle is embedded in the DMG, then the DMG):

```bash
OPEN_ISLAND_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
OPEN_ISLAND_NOTARY_PROFILE="open-island-notary" \
zsh scripts/package-app.sh
```

That path expects `xcrun notarytool store-credentials` to have been run ahead of time.

## Optional Overrides

The script accepts these environment variables:

- `OPEN_ISLAND_APP_NAME`
- `OPEN_ISLAND_BUNDLE_ID`
- `OPEN_ISLAND_VERSION`
- `OPEN_ISLAND_BUILD_NUMBER`
- `OPEN_ISLAND_PACKAGE_ROOT`
- `OPEN_ISLAND_BUNDLE_DIR`
- `OPEN_ISLAND_ZIP_PATH`
- `OPEN_ISLAND_SIGN_IDENTITY`
- `OPEN_ISLAND_NOTARY_PROFILE`

## Personal Build ("Mitama Island")

`zsh scripts/package-mitama-island.sh` wraps `package-app.sh` to produce and
install a personally branded build (own name, bundle identifier
`dev.mitama.island`, own entitlements, Sparkle automatic-update checks
disabled) instead of the upstream `Open Island` product. It signs with the
local `Open Island Dev Local` identity created by `setup-dev-signing.sh`, so
Accessibility/Automation TCC grants survive reinstalls.

**`MITAMA_ISLAND_VERSION` should always be set explicitly.** If it is left
unset, the script falls back to `git describe --tags --abbrev=0`, which
resolves to the nearest upstream release tag (for example `v1.1.7`) — not a
version tracking this fork's own history — so an unset variable silently
ships an upstream version string on the personal build.

```bash
MITAMA_ISLAND_VERSION=2.27.0 zsh scripts/package-mitama-island.sh
```

Set `MITAMA_ISLAND_INSTALL=false` to build without replacing the installed
copy at `/Applications/Mitama Island.app`.

## Dev Quick Launch

`zsh scripts/launch-dev-app.sh` rebuilds `~/Applications/Open Island Dev.app`
from a debug build and always re-runs `OpenIslandSetup install` first, which
(re-)writes every supported agent's hook config. Pass `--skip-setup` to skip
that step on a plain rebuild-and-relaunch cycle — useful when iterating
quickly and the hook configs are already known to be current:

```bash
zsh scripts/launch-dev-app.sh --skip-setup
```
