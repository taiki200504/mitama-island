#!/bin/zsh
# The bundled sound catalog only means something if every cue name the app can
# resolve actually ships a file, and every shipped file is reachable from
# somewhere in the app. A name added to a switch statement without its file is
# a silent fallback to a system sound; a file added without a reference is
# dead weight nobody remembers to remove.

set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

python3 - <<'PY'
import pathlib
import re
import sys

sounds_dir = pathlib.Path("Sources/OpenIslandApp/Resources/Sounds")
shipped = {path.stem for path in sounds_dir.glob("*.caf")}

# Every place a "ui-*" cue name appears as a string literal.
sources = [
    pathlib.Path("Sources/OpenIslandApp/Theme/IslandTheme.swift"),
    pathlib.Path("Sources/OpenIslandApp/Linkstart/LinkstartOverlayController.swift"),
    pathlib.Path("Sources/OpenIslandApp/NotificationSoundService.swift"),
]
referenced: set[str] = set()
for source in sources:
    referenced |= set(re.findall(r'"(ui-[a-z-]+)"', source.read_text()))

# ui-hover ships deliberately unused — see NotificationSoundService.play's
# doc comment: a menu-bar-resident app should not chime on every pointer pass.
known_unused = {"ui-hover"}

missing = sorted(referenced - shipped)
unused = sorted(shipped - referenced - known_unused)

failed = False
if missing:
    failed = True
    print("These cue names are referenced in code but ship no .caf file:")
    for name in missing:
        print(f"  {name}.caf")
if unused:
    failed = True
    print("These .caf files ship but nothing in the app refers to them:")
    for name in unused:
        print(f"  {name}.caf")

if failed:
    print("")
    print("Add the missing file, reference the orphaned one, or delete it.")
    sys.exit(1)

print(f"All {len(shipped)} bundled sound files are accounted for.")
PY
