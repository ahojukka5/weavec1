#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

CHECKOUT="$TMP/weavec1"
TOOLS="$TMP/tools"
mkdir -p "$CHECKOUT/scripts" "$CHECKOUT/build/vendor/weavec0-source" \
  "$CHECKOUT/build" "$CHECKOUT/test" "$TOOLS"

cp "$ROOT/scripts/package-macos-sdk.sh" "$CHECKOUT/scripts/"
printf '# test\n' > "$CHECKOUT/README.md"
printf 'license\n' > "$CHECKOUT/LICENSE"
printf 'notice\n' > "$CHECKOUT/NOTICE"
printf '(core-module (core-version 2) (decls))\n' \
  > "$CHECKOUT/test/10_string_literal.wir"
printf 'int weave_runtime_stub(void) { return 0; }\n' \
  > "$CHECKOUT/build/vendor/weavec0-source/runtime.c"
printf 'int weave_runtime_stub(void);\n' \
  > "$CHECKOUT/build/vendor/weavec0-source/runtime.h"

cat > "$CHECKOUT/build/weavec1" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '; fake llvm\n' > "$2"
EOF
chmod +x "$CHECKOUT/build/weavec1"

cat > "$TOOLS/uname" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  -s) printf 'Darwin\n' ;;
  -m) printf 'arm64\n' ;;
  *) printf 'Darwin\n' ;;
esac
EOF

cat > "$TOOLS/clang" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=""
compile_only=0
while (($#)); do
  case "$1" in
    -o) output="$2"; shift 2 ;;
    -c) compile_only=1; shift ;;
    *) shift ;;
  esac
done
[[ -n "$output" ]]
if (( compile_only )); then
  printf 'object\n' > "$output"
else
  cat > "$output" <<'PROGRAM'
#!/usr/bin/env bash
exit 42
PROGRAM
  chmod +x "$output"
fi
EOF

cat > "$TOOLS/ar" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'archive\n' > "$2"
EOF

cat > "$TOOLS/otool" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
binary="${*: -1}"
printf '%s:\n' "$binary"
printf '\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1.0.0)\n'
EOF

cat > "$TOOLS/file" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat > "$TOOLS/strip" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TOOLS"/*

(
  cd "$CHECKOUT"
  PATH="$TOOLS:$PATH" scripts/package-macos-sdk.sh v0.3.2 dist
)

archive="$CHECKOUT/dist/weavec1-v0.3.2-macos-arm64.tar.gz"
[[ -s "$archive" ]]
tar -tzf "$archive" | grep -Fq \
  'weavec1-v0.3.2-macos-arm64/bin/weavec1'
tar -tzf "$archive" | grep -Fq \
  'weavec1-v0.3.2-macos-arm64/lib/libweave-runtime.a'
tar -tzf "$archive" | grep -Fq \
  'weavec1-v0.3.2-macos-arm64/include/runtime.h'

printf 'package-macos-sdk: deterministic package harness passed\n'
