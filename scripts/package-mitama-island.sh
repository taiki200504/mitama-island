#!/bin/zsh
#
# Builds the personal "Mitama Island" bundle and installs it to /Applications.
#
# Why this exists
# ---------------
# `launch-dev-app.sh` produces a debug bundle in ~/Applications that is meant
# to be rebuilt constantly. This script produces the build you actually live
# with: release configuration, own name and bundle identifier, own icon, and
# Sparkle's automatic update check turned off so it never tries to replace
# this fork with an upstream release.
#
# Signing reuses the local identity from `setup-dev-signing.sh`, so the
# Accessibility and Automation grants survive reinstalls.
#
# Usage:
#   zsh scripts/package-mitama-island.sh            # build + install
#   MITAMA_ISLAND_INSTALL=false zsh scripts/…       # build only

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
install_app="${MITAMA_ISLAND_INSTALL:-true}"
app_name="Mitama Island"
install_path="/Applications/$app_name.app"

signing_identity="${OPEN_ISLAND_SIGN_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
    if security find-identity -p codesigning -v 2>/dev/null | grep -q '"Open Island Dev Local"'; then
        signing_identity="Open Island Dev Local"
    else
        echo "No signing identity found. Run: zsh scripts/setup-dev-signing.sh" >&2
        exit 1
    fi
fi

version="${MITAMA_ISLAND_VERSION:-$(git -C "$repo_root" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo 1.0.0)}"

echo "• Building $app_name $version (signed as \"$signing_identity\")…"

OPEN_ISLAND_APP_NAME="$app_name" \
OPEN_ISLAND_BUNDLE_ID="dev.mitama.island" \
OPEN_ISLAND_VERSION="$version" \
OPEN_ISLAND_SIGN_IDENTITY="$signing_identity" \
OPEN_ISLAND_SU_FEED_URL="" \
 OPEN_ISLAND_ENTITLEMENTS="$repo_root/config/packaging/MitamaIsland.entitlements" \
OPEN_ISLAND_SU_AUTOMATIC_CHECKS="false" \
    zsh "$repo_root/scripts/package-app.sh"

built_bundle="$repo_root/output/package/$app_name.app"
if [[ ! -d "$built_bundle" ]]; then
    echo "Expected bundle missing: $built_bundle" >&2
    exit 1
fi

if [[ "$install_app" != "true" ]]; then
    echo "✓ Built $built_bundle (install skipped)."
    exit 0
fi

# Quit a running copy first; macOS refuses to replace a bundle in use.
osascript -e "tell application \"$app_name\" to quit" 2>/dev/null || true
pkill -f "$app_name.app/Contents/MacOS" 2>/dev/null || true
sleep 1

rm -rf "$install_path"
# `ditto`, not `cp -R`: frameworks are symlink farms (Versions/Current), and
# `cp -R` resolves those symlinks into copies, after which dyld cannot find
# @rpath/Sparkle.framework/Versions/B/Sparkle and the app aborts at launch.
ditto "$built_bundle" "$install_path"
echo "✓ Installed $install_path"

codesign --verify --deep --strict "$install_path" \
    || { echo "Installed bundle failed signature verification." >&2; exit 1; }

open -a "$install_path"
echo "✓ Launched. Enable 'ログイン時に起動' in Settings → 一般 to start it at login."
