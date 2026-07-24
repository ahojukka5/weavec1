#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

usage() {
  cat <<'EOF'
usage: scripts/package-linux-sdk.sh <glibc|musl> <version> [output-dir]

Package the already-built weavec1 compiler as a static Linux x86-64 SDK.
Run ./build.sh first with the matching WEAVEC0_LIBC value.
EOF
}

if [[ $# -lt 2 || $# -gt 3 ]]; then
  usage >&2
  exit 2
fi

LIBC="$1"
VERSION="$2"
OUTPUT_DIR="${3:-dist}"

case "$LIBC" in
  glibc|musl) ;;
  *)
    printf 'unsupported libc: %s\n' "$LIBC" >&2
    usage >&2
    exit 2
    ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEAVEC0_VERSION="${WEAVEC0_VERSION:-v0.2.1}"
WEAVEC0_PACKAGE="weavec0-${WEAVEC0_VERSION}-linux-x86_64-${LIBC}"
DEFAULT_WEAVEC0_SDK="$ROOT/build/vendor/weavec0-sdk/$WEAVEC0_PACKAGE"
WEAVEC0_SDK="${WEAVEC0_SDK:-$DEFAULT_WEAVEC0_SDK}"

PACKAGE_NAME="weavec1-${VERSION}-linux-x86_64-${LIBC}"
RELEASE_BUILD="$ROOT/build/release/$LIBC"
PACKAGE_DIR="$RELEASE_BUILD/$PACKAGE_NAME"
ARCHIVE_DIR="$ROOT/$OUTPUT_DIR"
ARCHIVE="$ARCHIVE_DIR/$PACKAGE_NAME.tar.gz"
COMPILER_SOURCE="$ROOT/build/weavec1"
COMPILER="$PACKAGE_DIR/bin/weavec1"
RUNTIME_SOURCE="$WEAVEC0_SDK/lib/libweavec0-runtime.a"
RUNTIME="$PACKAGE_DIR/lib/libweave-runtime.a"
HEADER_SOURCE="$WEAVEC0_SDK/include/runtime.h"
SMOKE_LL="$RELEASE_BUILD/smoke.ll"
SMOKE_OBJECT="$RELEASE_BUILD/smoke.o"
SMOKE_EXE="$RELEASE_BUILD/smoke"

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'required tool not found: %s\n' "$1" >&2
    exit 1
  }
}

require_tool clang
require_tool file
require_tool readelf
require_tool tar

if [[ "$LIBC" == musl ]]; then
  require_tool musl-gcc
fi

[[ -x "$COMPILER_SOURCE" ]] || {
  printf 'missing compiler: %s\n' "$COMPILER_SOURCE" >&2
  printf 'run WEAVEC0_LIBC=%s ./build.sh first\n' "$LIBC" >&2
  exit 1
}
[[ -s "$RUNTIME_SOURCE" ]] || {
  printf 'missing runtime library: %s\n' "$RUNTIME_SOURCE" >&2
  exit 1
}
[[ -f "$HEADER_SOURCE" ]] || {
  printf 'missing runtime header: %s\n' "$HEADER_SOURCE" >&2
  exit 1
}

rm -rf "$RELEASE_BUILD"
mkdir -p "$PACKAGE_DIR/bin" "$PACKAGE_DIR/lib" \
  "$PACKAGE_DIR/include" "$ARCHIVE_DIR"

cp "$COMPILER_SOURCE" "$COMPILER"
cp "$RUNTIME_SOURCE" "$RUNTIME"
cp "$HEADER_SOURCE" "$PACKAGE_DIR/include/runtime.h"
chmod 0755 "$COMPILER"

if readelf -l "$COMPILER" | grep -q 'INTERP'; then
  printf 'compiler is dynamically linked: %s\n' "$COMPILER" >&2
  readelf -l "$COMPILER" >&2
  exit 1
fi

file "$COMPILER"

cat > "$PACKAGE_DIR/SDK-MANIFEST" <<EOF
name=weavec1
version=$VERSION
platform=linux-x86_64
libc=$LIBC
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
clang -Wno-override-module -O2 -c "$SMOKE_LL" -o "$SMOKE_OBJECT"
case "$LIBC" in
  glibc)
    clang -static "$SMOKE_OBJECT" "$RUNTIME" -o "$SMOKE_EXE"
    ;;
  musl)
    musl-gcc -static "$SMOKE_OBJECT" "$RUNTIME" -o "$SMOKE_EXE"
    ;;
esac

set +e
"$SMOKE_EXE" >/dev/null
status=$?
set -e
if [[ "$status" != 42 ]]; then
  printf 'SDK smoke executable returned %s, expected 42\n' "$status" >&2
  exit 1
fi

if command -v strip >/dev/null 2>&1; then
  strip --strip-unneeded "$COMPILER"
fi

rm -f "$ARCHIVE"
tar -C "$RELEASE_BUILD" -czf "$ARCHIVE" "$PACKAGE_NAME"
printf '%s\n' "$ARCHIVE"
