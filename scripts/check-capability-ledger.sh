#!/bin/zsh
# The pending-capability ledger only means something if every case in it is
# actually attached to a control. Cases added "for later" turn the ledger into a
# wish list, and then nobody trusts the badges either.

set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

python3 - <<'PY'
import pathlib, re, sys

ledger = pathlib.Path("Sources/OpenIslandApp/Settings/FeatureAvailability.swift")
text = ledger.read_text()
# The file also holds FeatureAvailability; only PendingCapability's cases count.
block = text[text.index("enum PendingCapability"):]
block = block[:block.index("\n}")]
cases = re.findall(r"^    case ([a-zA-Z]+)$", block, re.M)

body = ""
for root in ("Sources", "Tests"):
    for path in pathlib.Path(root).rglob("*.swift"):
        if path.name != ledger.name:
            body += path.read_text()

unused = [c for c in cases if not re.search(rf"\.{c}\b", body)]
missing_string = []
strings = pathlib.Path("Sources/OpenIslandApp/Resources/en.lproj/Localizable.strings").read_text()
for c in cases:
    if f'"settings.pending.{c}"' not in strings:
        missing_string.append(c)

failed = False
if unused:
    failed = True
    print("These capabilities are in the ledger but no control uses them:")
    for c in unused:
        print(f"  {c}")
    print("Attach them to a control, or remove them until something needs them.")
if missing_string:
    failed = True
    print("These capabilities have no explanation string:")
    for c in missing_string:
        print(f"  settings.pending.{c}")

if failed:
    sys.exit(1)

print(f"All {len(cases)} pending capabilities are attached to a control.")
PY
