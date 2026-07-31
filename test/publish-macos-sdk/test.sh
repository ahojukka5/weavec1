#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec1-publish-sdk-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

CHECKOUT="$TMP/checkout"
FAKEBIN="$TMP/bin"
CAPTURE="$TMP/capture"
STATE="$TMP/release-exists"
mkdir -p "$CHECKOUT/scripts" "$FAKEBIN" "$CAPTURE"
cp "$ROOT/scripts/publish-macos-sdk.sh" "$CHECKOUT/scripts/"
printf '0.3.2\n' > "$CHECKOUT/VERSION"
chmod +x "$CHECKOUT/scripts/publish-macos-sdk.sh"

cat > "$CHECKOUT/scripts/package-macos-sdk.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
version="$1"
out="${2:-dist}"
mkdir -p "$out"
archive="$out/weavec1-${version}-macos-arm64.tar.gz"
printf 'archive\n' > "$archive"
printf '%s\n' "$archive"
EOF
chmod +x "$CHECKOUT/scripts/package-macos-sdk.sh"

cat > "$FAKEBIN/uname" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  -s) printf 'Darwin\n' ;;
  -m) printf 'arm64\n' ;;
  *) printf 'Darwin\n' ;;
esac
EOF
chmod +x "$FAKEBIN/uname"

cat > "$FAKEBIN/git" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  status)
    [[ -z "${WEAVEC1_TEST_DIRTY:-}" ]] || printf '?? unexpected-file\n'
    exit 0
    ;;
  rev-parse) printf 'deadbeefcafebabe\n' ;;
  *) printf 'unexpected git invocation: %s\n' "$*" >&2; exit 2 ;;
esac
EOF
chmod +x "$FAKEBIN/git"

cat > "$FAKEBIN/shasum" <<'EOF'
#!/usr/bin/env bash
printf '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef  %s\n' "${@: -1}"
EOF
chmod +x "$FAKEBIN/shasum"

cat > "$FAKEBIN/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$WEAVEC1_TEST_GH_LOG"

if [[ "$1" == auth && "$2" == status ]]; then
  exit 0
fi

if [[ "$1" == release && "$2" == view ]]; then
  if [[ "$*" == *'--json assets'* ]]; then
    printf '%s\n' \
      'weavec1-v0.3.2-macos-arm64.tar.gz' \
      'SHA256SUMS'
    exit 0
  fi
  if [[ "$*" == *'--json url'* ]]; then
    printf 'https://github.example/release/v0.3.2\n'
    exit 0
  fi
  [[ -f "$WEAVEC1_TEST_RELEASE_STATE" ]]
  exit $?
fi

if [[ "$1" == release && "$2" == download ]]; then
  out=""
  while (($#)); do
    if [[ "$1" == --dir ]]; then
      out="$2"
      break
    fi
    shift
  done
  mkdir -p "$out"
  printf '%s  %s\n' \
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
    'weavec1-v0.3.1-linux-x86_64-glibc.tar.gz' > "$out/SHA256SUMS"
  exit 0
fi

if [[ "$1" == release && "$2" == create ]]; then
  touch "$WEAVEC1_TEST_RELEASE_STATE"
  for arg in "$@"; do
    [[ "$(basename -- "$arg")" == SHA256SUMS ]] && \
      cp "$arg" "$WEAVEC1_TEST_CAPTURE/create-SHA256SUMS"
  done
  exit 0
fi

if [[ "$1" == release && "$2" == upload ]]; then
  for arg in "$@"; do
    [[ "$(basename -- "$arg")" == SHA256SUMS ]] && \
      cp "$arg" "$WEAVEC1_TEST_CAPTURE/upload-SHA256SUMS"
  done
  exit 0
fi

printf 'unexpected gh invocation: %s\n' "$*" >&2
exit 2
EOF
chmod +x "$FAKEBIN/gh"

export PATH="$FAKEBIN:$PATH"
export WEAVEC1_TEST_GH_LOG="$CAPTURE/gh.log"
export WEAVEC1_TEST_RELEASE_STATE="$STATE"
export WEAVEC1_TEST_CAPTURE="$CAPTURE"

set +e
(
  cd "$CHECKOUT"
  WEAVEC1_TEST_DIRTY=1 scripts/publish-macos-sdk.sh \
    > "$CAPTURE/dirty.out" 2> "$CAPTURE/dirty.err"
)
dirty_status="$?"
set -e
[[ "$dirty_status" -ne 0 ]]
grep -Fq 'working tree must be clean' "$CAPTURE/dirty.err"

(
  cd "$CHECKOUT"
  scripts/publish-macos-sdk.sh > "$CAPTURE/create.out"
)
grep -Fq 'release create v0.3.2' "$CAPTURE/gh.log"
grep -Fq -- '--target deadbeefcafebabe' "$CAPTURE/gh.log"
grep -Fq 'weavec1-v0.3.2-macos-arm64.tar.gz' \
  "$CAPTURE/create-SHA256SUMS"
grep -Fq 'https://github.example/release/v0.3.2' "$CAPTURE/create.out"

: > "$CAPTURE/gh.log"
(
  cd "$CHECKOUT"
  scripts/publish-macos-sdk.sh > "$CAPTURE/update.out"
)
grep -Fq 'release download v0.3.2' "$CAPTURE/gh.log"
grep -Fq 'release upload v0.3.2' "$CAPTURE/gh.log"
grep -Fq 'weavec1-v0.3.1-linux-x86_64-glibc.tar.gz' \
  "$CAPTURE/upload-SHA256SUMS"
grep -Fq 'weavec1-v0.3.2-macos-arm64.tar.gz' \
  "$CAPTURE/upload-SHA256SUMS"
[[ "$(wc -l < "$CAPTURE/upload-SHA256SUMS" | tr -d ' ')" == 2 ]]

echo 'publish-macos-sdk: dirty, create, and update paths passed'
