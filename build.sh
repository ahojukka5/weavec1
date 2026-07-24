#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

# =============================================================================
# weavec1 — Stage 1 compiler build and bootstrap-determinism ladder
# =============================================================================
#
# Linux x86-64 builds consume the published weavec0 bootstrap SDK by default.
# The SDK supplies the Stage 0 compiler executable, reusable bootstrap object,
# and a libc-specific static runtime library. No weavec0 source build is needed.
#
# Environment overrides:
#
#   WEAVEC0_SDK=/path/to/extracted/sdk
#       Use an already extracted SDK directory.
#
#   WEAVEC0_VERSION=v0.2.1
#       Select the published weavec0 SDK release.
#
#   WEAVEC0_LIBC=glibc|musl
#       Select the Linux SDK and linker. Default: glibc.
#
#   WEAVEC0=/path/to/weavec0/source
#       Backwards-compatible source-tree override. Used directly after running
#       that tree's build.sh when necessary.
#
#   WEAVEC0_TAG=v0.2.1
#       Source fallback tag for platforms without a published SDK.
# =============================================================================

REGEN_GOLDENS=0
for arg in "$@"; do
  case "$arg" in
    --regen-goldens) REGEN_GOLDENS=1 ;;
    -h|--help)
      sed -n '4,38p' "$0"
      exit 0
      ;;
    *) printf 'unknown flag: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

WEAVEC1_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$WEAVEC1_DIR/src"
TEST_DIR="$WEAVEC1_DIR/test"
BUILD_DIR="$WEAVEC1_DIR/build"
SRC_LL_DIR="$BUILD_DIR/src-ll"
SELFHOST_SRC_LL_DIR="$BUILD_DIR/src2-ll"
LINK_LL_DIR="$BUILD_DIR/link-ll"
SELFHOST_LINK_LL_DIR="$BUILD_DIR/link2-ll"
OBJ_DIR="$BUILD_DIR/obj"
SELFHOST_OBJ_DIR="$BUILD_DIR/obj2"
TEST_LL_DIR="$BUILD_DIR/test-ll"
SELFHOST_TEST_LL_DIR="$BUILD_DIR/test2-ll"
TEST_EXE_DIR="$BUILD_DIR/test-bin"
SELFHOST_TEST_EXE_DIR="$BUILD_DIR/test2-bin"
MANIFEST="$TEST_DIR/manifest.txt"

WEAVEC0_VERSION="${WEAVEC0_VERSION:-v0.2.1}"
WEAVEC0_TAG="${WEAVEC0_TAG:-$WEAVEC0_VERSION}"
WEAVEC0_LIBC="${WEAVEC0_LIBC:-glibc}"
WEAVEC0_RELEASE_BASE="${WEAVEC0_RELEASE_BASE:-https://github.com/ahojukka5/weavec0/releases/download}"
WEAVEC0_REPO="https://github.com/ahojukka5/weavec0.git"

DEPENDENCY_MODE=""
BOOTSTRAP_DIR=""
BOOTSTRAP_OBJECT=""
BOOTSTRAP_RUNTIME_LIBRARY=""
BOOTSTRAP_BC_DIR=""
WEAVEC0_COMPILER=""

WEAVEC1="$BUILD_DIR/weavec1"
WEAVEC1_SELFHOST="$BUILD_DIR/weavec1-selfhost"

MODULES=(
  runtime_bindings
  strings
  tokens

  ast_kinds
  ast_storage
  ast_accessors
  ast_constructors

  lexer

  parser_state
  parser_expect
  parser_types
  parser_expr
  parser_stmt
  parser_decl
  parser_entry

  emit_context
  emit_text
  emit_names
  emit_types
  emit_sections
  emit_strings
  emit_expr
  emit_calls
  emit_stmt
  emit_control_flow
  emit_declarations
  emit_module

  driver_diag
  driver
  main
)

BOOTSTRAP_MODULES=(
  01_runtime_bindings
  02_strings
  03_tokens
  04_lexer
  05_ast
  06_parser
  07_emit_llvm
  08_driver
)

log()  { printf '[weavec1] %s\n' "$*" >&2; }
fail() { printf '[weavec1] error: %s\n' "$*" >&2; exit 1; }
require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "required tool not found: $1"
}

host_has_published_sdk() {
  [[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]]
}

validate_sdk() {
  local sdk="$1"
  [[ -x "$sdk/bin/weavec0" ]] || fail "SDK compiler missing: $sdk/bin/weavec0"
  [[ -s "$sdk/lib/weavec0-bootstrap.o" ]] || \
    fail "SDK bootstrap object missing: $sdk/lib/weavec0-bootstrap.o"
  [[ -s "$sdk/lib/libweavec0-runtime.a" ]] || \
    fail "SDK runtime library missing: $sdk/lib/libweavec0-runtime.a"

  BOOTSTRAP_DIR="$sdk"
  WEAVEC0_COMPILER="$sdk/bin/weavec0"
  BOOTSTRAP_OBJECT="$sdk/lib/weavec0-bootstrap.o"
  BOOTSTRAP_RUNTIME_LIBRARY="$sdk/lib/libweavec0-runtime.a"
  DEPENDENCY_MODE=sdk
}

download_weavec0_sdk() {
  require_tool curl
  require_tool sha256sum
  require_tool tar

  case "$WEAVEC0_LIBC" in
    glibc|musl) ;;
    *) fail "WEAVEC0_LIBC must be glibc or musl" ;;
  esac

  local package="weavec0-${WEAVEC0_VERSION}-linux-x86_64-${WEAVEC0_LIBC}"
  local archive="$package.tar.gz"
  local vendor_root="$BUILD_DIR/vendor/weavec0-sdk"
  local sdk="$vendor_root/$package"
  local cache="$BUILD_DIR/downloads"
  local archive_path="$cache/$archive"
  local sums_path="$cache/weavec0-${WEAVEC0_VERSION}-SHA256SUMS"
  local release_url="$WEAVEC0_RELEASE_BASE/$WEAVEC0_VERSION"

  if [[ -d "$sdk" ]]; then
    log "using cached weavec0 SDK: $sdk"
    validate_sdk "$sdk"
    return
  fi

  mkdir -p "$cache" "$vendor_root"
  log "downloading weavec0 SDK $WEAVEC0_VERSION ($WEAVEC0_LIBC)"
  curl --fail --location --retry 3 --output "$archive_path" \
    "$release_url/$archive"
  curl --fail --location --retry 3 --output "$sums_path" \
    "$release_url/SHA256SUMS"

  local expected
  expected="$(awk -v name="$archive" '$2 == name { print $1; exit }' "$sums_path")"
  [[ -n "$expected" ]] || fail "checksum not found for $archive"
  printf '%s  %s\n' "$expected" "$archive_path" | sha256sum --check -

  rm -rf "$sdk"
  tar -C "$vendor_root" -xzf "$archive_path"
  validate_sdk "$sdk"
}

ensure_weavec0_source() {
  require_tool git

  if [[ -n "${WEAVEC0:-}" ]]; then
    BOOTSTRAP_DIR="$WEAVEC0"
    log "using weavec0 source tree from WEAVEC0: $BOOTSTRAP_DIR"
  else
    BOOTSTRAP_DIR="$BUILD_DIR/vendor/weavec0-source"
    if [[ ! -d "$BOOTSTRAP_DIR/.git" ]]; then
      log "fetching weavec0 source fallback $WEAVEC0_TAG"
      mkdir -p "$(dirname "$BOOTSTRAP_DIR")"
      git clone --depth 1 --branch "$WEAVEC0_TAG" "$WEAVEC0_REPO" \
        "$BOOTSTRAP_DIR"
    fi
  fi

  [[ -x "$BOOTSTRAP_DIR/build.sh" ]] || \
    fail "weavec0 build.sh missing: $BOOTSTRAP_DIR/build.sh"

  if [[ ! -x "$BOOTSTRAP_DIR/weavec0" ]] || \
     [[ ! -d "$BOOTSTRAP_DIR/build/bootstrap-tests/bc" ]]; then
    log "building weavec0 source fallback"
    (cd "$BOOTSTRAP_DIR" && ./build.sh)
  fi

  WEAVEC0_COMPILER="$BOOTSTRAP_DIR/weavec0"
  BOOTSTRAP_BC_DIR="$BOOTSTRAP_DIR/build/bootstrap-tests/bc"
  [[ -x "$WEAVEC0_COMPILER" ]] || fail "weavec0 compiler was not built"
  [[ -d "$BOOTSTRAP_BC_DIR" ]] || fail "weavec0 bitcode directory missing"
  DEPENDENCY_MODE=source
}

ensure_weavec0() {
  if [[ -n "${WEAVEC0_SDK:-}" ]]; then
    log "using WEAVEC0_SDK: $WEAVEC0_SDK"
    validate_sdk "$WEAVEC0_SDK"
  elif host_has_published_sdk; then
    download_weavec0_sdk
  else
    log "no published SDK for $(uname -s)/$(uname -m); using source fallback"
    ensure_weavec0_source
  fi
}

compile_module() {
  local compiler="$1"
  local output_dir="$2"
  local name="$3"
  local src="src/${name}.wir"
  local ll="$output_dir/${name}.ll"

  [[ -f "$src" ]] || fail "missing source module: $src"
  log "compile src/$name.wir"
  "$compiler" "$src" "$ll"
  [[ -s "$ll" ]] || fail "compiler produced empty LLVM IR for $name"
}

prepare_link_modules() {
  local src_ll_dir="$1"
  local link_ll_dir="$2"
  local compiler_name="$3"

  local all_decls="$BUILD_DIR/$compiler_name.decls.ll"
  {
    printf 'declare i32 @puts(ptr)\n'
    printf 'declare ptr @malloc(i64)\n'
    printf 'declare void @free(ptr)\n'
    printf 'declare ptr @realloc(ptr, i64)\n'
    printf 'declare ptr @memcpy(ptr, ptr, i64)\n'
    printf 'declare i64 @strlen(ptr)\n'
    printf 'declare i32 @strcmp(ptr, ptr)\n'
    printf 'declare i32 @strncmp(ptr, ptr, i64)\n'
    printf 'declare i32 @atoi(ptr)\n'
    printf 'declare i32 @putchar(i32)\n'
    printf 'declare ptr @weave_rt_read_file(ptr, ptr)\n'
    printf 'declare i32 @weave_rt_write_file(ptr, ptr, i64)\n'
    printf 'declare void @weave_rt_fatal(ptr)\n'

    local module
    for module in "${MODULES[@]}"; do
      awk '
        /^define / {
          signature = $0
          gsub(/\{[[:space:]]*$/, "", signature)
          sub(/^define /, "declare ", signature)
          print signature
        }
      ' "$src_ll_dir/${module}.ll"
    done
  } > "$all_decls"

  local module
  for module in "${MODULES[@]}"; do
    local src_ll="$src_ll_dir/${module}.ll"
    local link_ll="$link_ll_dir/${module}.ll"
    local names="$BUILD_DIR/$compiler_name.${module}.names"
    local decls="$BUILD_DIR/$compiler_name.${module}.decls.ll"

    awk '/^(define|declare) / {
      if (match($0, /@[A-Za-z0-9_.$-]+/)) {
        print substr($0, RSTART, RLENGTH)
      }
    }' "$src_ll" > "$names"

    awk 'NR == FNR {
      skip[$1] = 1
      next
    }
    {
      if (match($0, /@[A-Za-z0-9_.$-]+/)) {
        name = substr($0, RSTART, RLENGTH)
        if (name in skip) next
      }
      print
    }' "$names" "$all_decls" > "$decls"

    {
      sed -n '1,/^$/p' "$src_ll"
      printf '; ---- generated cross-module declarations ----\n'
      cat "$decls"
      printf '\n'
      sed '1,/^$/d' "$src_ll"
    } > "$link_ll"
  done
}

link_compiler_from_sdk() {
  local compiler_name="$1"
  local link_ll_dir="$2"
  local obj_dir="$3"
  local output="$4"

  mkdir -p "$obj_dir"
  rm -f "$obj_dir"/*.o

  local objects=()
  local module
  for module in "${MODULES[@]}"; do
    local object="$obj_dir/${module}.o"
    clang -Wno-override-module -O2 -c "$link_ll_dir/${module}.ll" -o "$object"
    objects+=("$object")
  done

  log "link $compiler_name with weavec0 SDK ($WEAVEC0_LIBC)"
  case "$WEAVEC0_LIBC" in
    glibc)
      clang -static "${objects[@]}" "$BOOTSTRAP_OBJECT" \
        "$BOOTSTRAP_RUNTIME_LIBRARY" -o "$output"
      ;;
    musl)
      require_tool musl-gcc
      musl-gcc -static "${objects[@]}" "$BOOTSTRAP_OBJECT" \
        "$BOOTSTRAP_RUNTIME_LIBRARY" -o "$output"
      ;;
  esac
}

link_compiler_from_source() {
  local compiler_name="$1"
  local link_ll_dir="$2"
  local output="$3"

  local llvm_modules=()
  local module
  for module in "${MODULES[@]}"; do
    llvm_modules+=("$link_ll_dir/${module}.ll")
  done

  local bootstrap_bitcode=()
  for module in "${BOOTSTRAP_MODULES[@]}"; do
    local bc="$BOOTSTRAP_BC_DIR/${module}.bc"
    [[ -f "$bc" ]] || fail "missing bootstrap bitcode: $bc"
    bootstrap_bitcode+=("$bc")
  done

  log "link $compiler_name with weavec0 source fallback"
  clang "${llvm_modules[@]}" "${bootstrap_bitcode[@]}" \
    "$BOOTSTRAP_DIR/runtime.c" -o "$output"
}

build_compiler() {
  local compiler="$1"
  local compiler_name="$2"
  local src_ll_dir="$3"
  local link_ll_dir="$4"
  local obj_dir="$5"
  local output="$6"

  log "building $compiler_name"
  mkdir -p "$src_ll_dir" "$link_ll_dir"
  rm -f "$src_ll_dir"/*.ll "$link_ll_dir"/*.ll

  local module
  for module in "${MODULES[@]}"; do
    compile_module "$compiler" "$src_ll_dir" "$module"
  done
  prepare_link_modules "$src_ll_dir" "$link_ll_dir" "$compiler_name"

  case "$DEPENDENCY_MODE" in
    sdk) link_compiler_from_sdk "$compiler_name" "$link_ll_dir" "$obj_dir" "$output" ;;
    source) link_compiler_from_source "$compiler_name" "$link_ll_dir" "$output" ;;
    *) fail "unknown weavec0 dependency mode: $DEPENDENCY_MODE" ;;
  esac
}

build_weavec1() {
  build_compiler "$WEAVEC0_COMPILER" "weavec1" "$SRC_LL_DIR" "$LINK_LL_DIR" \
    "$OBJ_DIR" "$WEAVEC1"
}

build_weavec1_selfhost() {
  build_compiler "$WEAVEC1" "weavec1-selfhost" "$SELFHOST_SRC_LL_DIR" "$SELFHOST_LINK_LL_DIR" \
    "$SELFHOST_OBJ_DIR" "$WEAVEC1_SELFHOST"
}

run_case() {
  local compiler="$1"
  local compiler_name="$2"
  local test_ll_dir="$3"
  local test_exe_dir="$4"
  local name="$5"
  local expected_exit="$6"

  local src="test/${name}.wir"
  local expected_ll="test/${name}.expected.ll"
  local ll="$test_ll_dir/${name}.ll"
  local bc="$test_ll_dir/${name}.bc"
  local exe="$test_exe_dir/${name}.out"

  [[ -f "$src" ]] || fail "missing test source: $src"
  log "compile test $name"
  "$compiler" "$src" "$ll"
  [[ -s "$ll" ]] || fail "$compiler_name produced empty LLVM IR for $name"

  llvm-as "$ll" -o "$bc"
  clang "$ll" -o "$exe"

  set +e
  "$exe"
  local actual_exit=$?
  set -e
  [[ "$actual_exit" == "$expected_exit" ]] || \
    fail "$name: expected exit $expected_exit, got $actual_exit"

  if [[ ! -f "$expected_ll" ]]; then
    if (( REGEN_GOLDENS )); then
      cp "$ll" "$expected_ll"
    else
      fail "missing expected LLVM IR: $expected_ll"
    fi
  elif ! diff -u "$expected_ll" "$ll" >/dev/null; then
    if (( REGEN_GOLDENS )); then
      cp "$ll" "$expected_ll"
    else
      diff -u "$expected_ll" "$ll" || true
      fail "$name: generated LLVM IR differs from expected fixture"
    fi
  fi
  log "ok $name"
}

run_compile_fail_case() {
  local compiler="$1"
  local compiler_name="$2"
  local test_ll_dir="$3"
  local name="$4"
  local expected_message="$5"

  local src="test/${name}.wir"
  local ll="$test_ll_dir/${name}.ll"
  local output="$test_ll_dir/${name}.compiler-output"

  rm -f "$ll" "$output"
  set +e
  "$compiler" "$src" "$ll" >"$output" 2>&1
  local status=$?
  set -e

  [[ "$status" != 0 ]] || fail "$name: expected $compiler_name failure"
  [[ ! -s "$ll" ]] || fail "$name: failed compile produced LLVM IR"
  grep -q "$expected_message" "$output" || \
    fail "$name: expected diagnostic containing: $expected_message"
  log "ok $name"
}

run_tests() {
  local compiler="$1"
  local compiler_name="$2"
  local test_ll_dir="$3"
  local test_exe_dir="$4"

  mkdir -p "$test_ll_dir" "$test_exe_dir"
  [[ -f "$MANIFEST" ]] || fail "missing test manifest: $MANIFEST"

  local kind name rest
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" ]] && continue
    read -r kind name rest <<<"$line"
    case "$kind" in
      pass) run_case "$compiler" "$compiler_name" "$test_ll_dir" \
        "$test_exe_dir" "$name" "$rest" ;;
      fail) run_compile_fail_case "$compiler" "$compiler_name" \
        "$test_ll_dir" "$name" "$rest" ;;
      *) fail "unknown manifest entry: $line" ;;
    esac
  done < "$MANIFEST"
  log "all $compiler_name tests passed"
}

compare_bootstrap_outputs() {
  log "comparing weavec1 and weavec1-selfhost output"
  local diverged=0
  local kind name rest
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" ]] && continue
    read -r kind name rest <<<"$line"
    [[ "$kind" == pass ]] || continue
    if ! diff -u "$TEST_LL_DIR/${name}.ll" "$SELFHOST_TEST_LL_DIR/${name}.ll" \
      >/dev/null; then
      printf '[bootstrap] DIVERGENCE: %s\n' "$name" >&2
      diverged=$((diverged + 1))
    fi
  done < "$MANIFEST"
  [[ "$diverged" == 0 ]] || fail "$diverged bootstrap output(s) diverged"
  log "bootstrap determinism validated"
}

main() {
  cd "$WEAVEC1_DIR"
  require_tool awk
  require_tool clang
  require_tool diff
  require_tool llvm-as
  ensure_weavec0
  build_weavec1
  run_tests "$WEAVEC1" "weavec1" "$TEST_LL_DIR" "$TEST_EXE_DIR"
  build_weavec1_selfhost
  run_tests "$WEAVEC1_SELFHOST" "weavec1-selfhost" "$SELFHOST_TEST_LL_DIR" "$SELFHOST_TEST_EXE_DIR"
  compare_bootstrap_outputs
}

main "$@"
