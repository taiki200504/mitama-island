#!/usr/bin/env zsh
# Fetches and builds MediaRemoteAdapter.framework (ungive/mediaremote-adapter,
# BSD-3-Clause) into vendor/mediaremote-adapter/ — never committed, see
# docs/references/mediaremote-adapter.md for why the framework has to be
# built from source rather than downloaded as a binary.
#
# Usage: zsh scripts/fetch-mediaremote-adapter.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="${REPO_ROOT}/vendor/mediaremote-adapter"

# Pinned to a specific commit, not a moving tag — this is a source tarball,
# not a signed release binary, so the commit SHA plus the tarball's own
# SHA256 is the only integrity check available. Bump both together when
# picking up a new upstream release.
PINNED_TAG="v0.7.7"
PINNED_COMMIT="e3ff5021eb0875858bd05f48d2e9ba2e962d1cf6"
PINNED_SHA256="adf2564265cbfbed6ee967cd44f70f774a78f681aaa41145c67730cad66f9277"
TARBALL_URL="https://github.com/ungive/mediaremote-adapter/archive/${PINNED_COMMIT}.tar.gz"

TARBALL_PATH="${VENDOR_DIR}/source.tar.gz"
SOURCE_DIR="${VENDOR_DIR}/src"
BUILD_DIR="${VENDOR_DIR}/build"

mkdir -p "$VENDOR_DIR"

echo "Fetching mediaremote-adapter ${PINNED_TAG} (${PINNED_COMMIT})"
curl -fsSL --max-time 30 -o "$TARBALL_PATH" "$TARBALL_URL"

actual_sha256="$(shasum -a 256 "$TARBALL_PATH" | awk '{print $1}')"
if [[ "$actual_sha256" != "$PINNED_SHA256" ]]; then
  echo "error: mediaremote-adapter tarball SHA256 mismatch" >&2
  echo "  expected: ${PINNED_SHA256}" >&2
  echo "  actual:   ${actual_sha256}" >&2
  echo "  This can mean upstream changed the tag, or something is tampering" >&2
  echo "  with the download. Do not proceed without re-verifying by hand." >&2
  rm -f "$TARBALL_PATH"
  exit 1
fi
echo "SHA256 verified"

rm -rf "$SOURCE_DIR"
mkdir -p "$SOURCE_DIR"
tar -xzf "$TARBALL_PATH" --strip-components=1 -C "$SOURCE_DIR"
rm -f "$TARBALL_PATH"

echo "Building MediaRemoteAdapter.framework"
cmake -S "$SOURCE_DIR" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build "$BUILD_DIR" --target MediaRemoteAdapter >/dev/null

FRAMEWORK_PATH="${BUILD_DIR}/MediaRemoteAdapter.framework"
if [[ ! -d "$FRAMEWORK_PATH" ]]; then
  echo "error: build finished but ${FRAMEWORK_PATH} is missing" >&2
  exit 1
fi

echo ""
echo "Built: ${FRAMEWORK_PATH}"
echo "scripts/package-app.sh picks this up automatically when it exists."
