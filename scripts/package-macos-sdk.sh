#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

usage() {
  cat <<'EOF'
usage: scripts/package-macos-sdk.sh <version> [output-dir]

Package the already-built weavec1 compiler as a native macOS SDK.
Run ./build.sh first on the target macOS architecture.
EOF
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage >&2
  exit 2
fi

[[ "$(uname -s)" == Darwin ]] || {
  printf 'package-macos-sdk: macOS host required\n' >&2
  exit 1
}

VERSION="$1"
OUTPUT_DIR="${2:-dist}"
ARCH="$(uname -m)"
case "$ARCH" in
  arm64|x86_64) ;;
  *)
    printf 'package-macos-sdk: unsupported architecture: %s\n' "$ARCH" >&2
    exit 1
    ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEAVEC0_VERSION="${WEAVEC0_VERSION:-v0.4.0}"
WEAVEC0_SOURCE="${WEAVEC0_SOURCE:-${WEAVEC0:-$ROOT/build/vendor/weavec0-source}}"
PACKAGE_NAME="weavec1-${VERSION}-macos-${ARCH}"
RELEASE_BUILD="$ROOT/build/release/macos-${ARCH}"
PACKAGE_DIR="$RELEASE_BUILD/$PACKAGE_NAME"
ARCHIVE_DIR="$ROOT/$OUTPUT_DIR"
ARCHIVE="$ARCHIVE_DIR/$PACKAGE_NAME.tar.gz"
COMPILER_SOURCE="$ROOT/build/weavec1"
COMPILER="$PACKAGE_DIR/bin/weavec1"
RUNTIME_SOURCE="$WEAVEC0_SOURCE/runtime.c"
HEADER_SOURCE="$WEAVEC0_SOURCE/runtime.h"
RUNTIME_OBJECT="$RELEASE_BUILD/runtime.o"
RUNTIME="$PACKAGE_DIR/lib/libweave-runtime.a"
SMOKE_LL="$RELEASE_BUILD/smoke.ll"
SMOKE_EXE="$RELEASE_BUILD/smoke"

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'required tool not found: %s\n' "$1" >&2
    exit 1
  }
}

require_tool ar
require_tool clang
require_tool file
require_tool otool
require_tool tar

[[ -x "$COMPILER_SOURCE" ]] || {
  printf 'missing compiler: %s\n' "$COMPILER_SOURCE" >&2
  printf 'run ./build.sh first on this macOS host\n' >&2
  exit 1
}
[[ -f "$RUNTIME_SOURCE" ]] || {
  printf 'missing Stage 0 runtime source: %s\n' "$RUNTIME_SOURCE" >&2
  exit 1
}
[[ -f "$HEADER_SOURCE" ]] || {
  printf 'missing Stage 0 runtime header: %s\n' "$HEADER_SOURCE" >&2
  exit 1
}

rm -rf "$RELEASE_BUILD"
mkdir -p "$PACKAGE_DIR/bin" "$PACKAGE_DIR/lib" \
  "$PACKAGE_DIR/include" "$ARCHIVE_DIR"

cp "$COMPILER_SOURCE" "$COMPILER"
cp "$HEADER_SOURCE" "$PACKAGE_DIR/include/runtime.h"
chmod 0755 "$COMPILER"

# macOS cannot produce a fully static executable (Apple's libSystem must
# always be linked dynamically), so a standalone release is instead required
# to depend on nothing beyond that always-present system library.
other_deps="$(otool -L "$COMPILER" | tail -n +2 | awk '{print $1}' | \
  grep -v '^/usr/lib/libSystem\.B\.dylib$' || true)"
if [[ -n "$other_deps" ]]; then
  printf 'release binary depends on more than libSystem:\n%s\n' "$other_deps" >&2
  otool -L "$COMPILER" >&2
  exit 1
fi

clang -O2 -c "$RUNTIME_SOURCE" -o "$RUNTIME_OBJECT"
ar rcs "$RUNTIME" "$RUNTIME_OBJECT"

file "$COMPILER"
file "$RUNTIME"

cat > "$PACKAGE_DIR/SDK-MANIFEST" <<EOF
name=weavec1
version=$VERSION
platform=macos-${ARCH}
compiler=bin/weavec1
runtime_library=lib/libweave-runtime.a
runtime_header=include/runtime.h
weavec0_sdk_version=$WEAVEC0_VERSION
EOF

printf '%s\n' "$VERSION" > "$PACKAGE_DIR/VERSION"
cp "$ROOT/README.md" "$PACKAGE_DIR/"
[[ -f "$ROOT/LICENSE" ]] && cp "$ROOT/LICENSE" "$PACKAGE_DIR/"
[[ -f "$ROOT/NOTICE" ]] && cp "$ROOT/NOTICE" "$PACKAGE_DIR/"

"$COMPILER" test/10_string_literal.wir "$SMOKE_LL"
clang "$SMOKE_LL" "$RUNTIME" -o "$SMOKE_EXE"
set +e
"$SMOKE_EXE" >/dev/null
status=$?
set -e
[[ "$status" == 42 ]] || {
  printf 'SDK smoke executable returned %s, expected 42\n' "$status" >&2
  exit 1
}

if command -v strip >/dev/null 2>&1; then
  strip -x "$COMPILER" 2>/dev/null || true
fi

rm -f "$ARCHIVE"
tar -C "$RELEASE_BUILD" -czf "$ARCHIVE" "$PACKAGE_NAME"
printf '%s\n' "$ARCHIVE"
