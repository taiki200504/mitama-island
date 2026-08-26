#!/bin/zsh
#
# `Bundle.module` traps instead of returning nil.
#
# SPM generates an accessor that only looks for the resource bundle at the .app
# root. A signed .app keeps its resources in Contents/Resources/, so the lookup
# misses and the generated accessor calls `fatalError` — the app dies at the
# first draw that touches a bundled resource, and only in the packaged build, so
# `swift run` and the tests stay green while the shipped app crashes on launch.
#
# `Bundle.appResources` (Sources/OpenIslandApp/ResourceBundle.swift) searches
# both locations and is the only sanctioned way in.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

offenders="$(grep -rn 'Bundle\.module' Sources | grep -v 'ResourceBundle.swift' || true)"

if [[ -n "$offenders" ]]; then
    echo "Bundle.module is unsafe in the packaged .app — use Bundle.appResources:" >&2
    echo "$offenders" >&2
    exit 1
fi

echo "No Bundle.module in shipped sources."
