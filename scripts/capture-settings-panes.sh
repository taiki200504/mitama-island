#!/bin/zsh
#
# Screenshots every settings pane.
#
# The artifact recorder already captures every visible window, so this only has
# to launch the app once per pane with that pane showing. Output lands beside the
# smoke artifacts and is meant to be eyeballed against the reference product.

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Pane capture runs only on macOS." >&2
    exit 1
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

timestamp="$(date +%Y%m%d-%H%M%S)"
root_dir="${OPEN_ISLAND_CAPTURE_DIR:-$repo_root/output/harness/panes-$timestamp}"
mkdir -p "$root_dir"

# Kept in step with SettingsTab.allCases; the check below fails if they drift.
panes=(
    general integrations notifications display appearance sound usage
    shortcuts sshRemote watch labs mitama about
)

# Only the SettingsTab block; SettingsSection lives further down the same file.
declared="$(sed -n '/^enum SettingsTab/,/^}/p' Sources/OpenIslandApp/Views/Settings/SettingsTab.swift \
    | grep -oE '^    case [a-z][a-zA-Z]*$' | awk '{print $2}' | sort | tr '\n' ' ')"
listed="$(printf '%s\n' "${panes[@]}" | sort | tr '\n' ' ')"
if [[ "$declared" != "$listed" ]]; then
    echo "Pane list is out of step with SettingsTab." >&2
    echo "  SettingsTab: $declared" >&2
    echo "  this script: $listed" >&2
    exit 1
fi

swift build --product OpenIslandApp >/dev/null

for pane in "${panes[@]}"; do
    pane_dir="$root_dir/$pane"
    mkdir -p "$pane_dir"

    echo "Capturing '$pane'"
    OPEN_ISLAND_HARNESS_SETTINGS_TAB="$pane" \
    OPEN_ISLAND_HARNESS_SCENARIO="sessionList" \
    OPEN_ISLAND_HARNESS_PRESENT_OVERLAY=0 \
    OPEN_ISLAND_HARNESS_START_BRIDGE=0 \
    OPEN_ISLAND_HARNESS_BOOT_ANIMATION=0 \
    OPEN_ISLAND_HARNESS_CAPTURE_DELAY_SECONDS=2 \
    OPEN_ISLAND_HARNESS_AUTO_EXIT_SECONDS=3 \
    OPEN_ISLAND_HARNESS_ARTIFACT_DIR="$pane_dir" \
        swift run OpenIslandApp >/dev/null 2>&1 || true

    if ! ls "$pane_dir"/*.png >/dev/null 2>&1; then
        echo "  no image captured for '$pane'" >&2
    fi
done

echo "Pane captures written to $root_dir"
