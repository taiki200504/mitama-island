#!/bin/zsh
# Validates all .strings files with plutil to catch syntax errors
# (unescaped quotes, bad Unicode, missing semicolons, etc.) early.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
failed=0

while IFS= read -r file; do
    if ! plutil -lint "$file" >/dev/null 2>&1; then
        echo "FAIL: $file"
        plutil -lint "$file" 2>&1 | sed 's/^/  /'
        failed=1
    fi
done < <(find "$repo_root/Sources" -name '*.strings' -type f)

if (( failed )); then
    echo ""
    echo "Localizable.strings validation failed. Common causes:"
    echo "  - Chinese quotes "" inside values (use「」or \\\" instead)"
    echo "  - Missing semicolons at end of lines"
    echo "  - Unescaped backslashes or special characters"
    exit 1
fi

echo "All .strings files passed validation."

# Every locale must carry exactly the same key set. A key added to one file and
# forgotten in another shows up as an English string inside a Japanese UI, which
# is the kind of thing nobody notices until a user reports it.
python3 - "$repo_root/Sources/OpenIslandApp/Resources" <<'PY'
import pathlib
import re
import sys

resources = pathlib.Path(sys.argv[1])
pattern = re.compile(r'^"([^"]+)"\s*=')

keys = {}
for directory in sorted(resources.glob("*.lproj")):
    locale = directory.name.removesuffix(".lproj")
    strings = directory / "Localizable.strings"
    if not strings.exists():
        continue
    keys[locale] = {
        match.group(1)
        for line in strings.read_text(encoding="utf-8").splitlines()
        if (match := pattern.match(line.strip()))
    }

if "en" not in keys:
    print("no en.lproj/Localizable.strings to compare against")
    raise SystemExit(1)

reference = keys["en"]
failed = False
for locale, present in sorted(keys.items()):
    if locale == "en":
        continue
    missing = sorted(reference - present)
    extra = sorted(present - reference)
    if missing or extra:
        failed = True
        print(f"FAIL: {locale}.lproj is out of step with en.lproj")
        for key in missing:
            print(f"  missing: {key}")
        for key in extra:
            print(f"  not in en: {key}")

if failed:
    print("")
    print("Add the key to every locale, or remove it everywhere.")
    raise SystemExit(1)

print(f"All {len(keys)} locales carry the same {len(reference)} keys.")
PY
