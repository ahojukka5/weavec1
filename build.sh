#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

# =============================================================================
# weavec1 — Stage 1 Weave compiler (WIR-written), build & test ladder
# =============================================================================
#
# Pipeline:
#
#   1. Acquire weavec0 (Stage 0 seed compiler). Either honour the WEAVEC0
#      environment variable (path to a pre-built weavec0 source tree), or
#      git-clone the pinned $WEAVEC0_TAG from upstream into build/vendor/
#      and build it there.
#   2. Compile every weavec1 WIR module under src/ with weavec0 → LLVM IR.
#   3. Link the modules with weavec0's compiler bitcode + runtime.c to
#      produce the weavec1 binary.
#   4. Run the test ladder (test/manifest.txt) through weavec1.
#   5. Repeat steps 2–4 with weavec1-compiled-by-weavec0 producing weavec2,
#      to confirm bootstrap determinism (weavec2 must emit byte-identical
#      LLVM IR to weavec1 on the shared test surface).
#
# Flags:
#
#   --regen-goldens
#       On any golden mismatch, overwrite the expected .ll with the just-
#       generated output instead of erroring. Review the resulting git
#       diff before committing.
#
# Environment:
#
#   WEAVEC0
#       Absolute path to an existing weavec0 source tree where ./build.sh
#       has already produced the bitcode artefacts under build/bootstrap-
#       tests/bc/. Skips the vendor-fetch entirely.
#
#   WEAVEC0_TAG  (default: v0.2.0)
#       Git tag/ref pulled from github.com/ahojukka5/weavec0 when no
#       WEAVEC0 is provided.
# =============================================================================

REGEN_GOLDENS=0
for arg in "$@"; do
  case "$arg" in
    --regen-goldens) REGEN_GOLDENS=1 ;;
    -h|--help)
      sed -n '4,40p' "$0"
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
SRC2_LL_DIR="$BUILD_DIR/src2-ll"
LINK_LL_DIR="$BUILD_DIR/link-ll"
LINK2_LL_DIR="$BUILD_DIR/link2-ll"
TEST_LL_DIR="$BUILD_DIR/test-ll"
TEST2_LL_DIR="$BUILD_DIR/test2-ll"
TEST_EXE_DIR="$BUILD_DIR/test-bin"
TEST2_EXE_DIR="$BUILD_DIR/test2-bin"
MANIFEST="$TEST_DIR/manifest.txt"

# weavec0 dependency. BOOTSTRAP_DIR is set by ensure_weavec0() below — either
# from the WEAVEC0 env var or from the auto-fetched vendor copy.
WEAVEC0_TAG="${WEAVEC0_TAG:-v0.2.0}"
WEAVEC0_REPO="https://github.com/ahojukka5/weavec0.git"
BOOTSTRAP_DIR=""
BOOTSTRAP_BC_DIR=""

WEAVEC1="$BUILD_DIR/weavec1"
WEAVEC2="$BUILD_DIR/weavec2"

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
require_tool() { command -v "$1" >/dev/null 2>&1 || fail "required tool not found: $1"; }

# Locate (or fetch + build) the weavec0 dependency. After this returns,
# $BOOTSTRAP_DIR points at a weavec0 source tree where ./build.sh has been
# run, and $BOOTSTRAP_BC_DIR points at its bitcode output directory.
ensure_weavec0() {
  if [[ -n "${WEAVEC0:-}" ]]; then
    BOOTSTRAP_DIR="$WEAVEC0"
    log "using WEAVEC0 from env: $BOOTSTRAP_DIR"
  else
    BOOTSTRAP_DIR="$BUILD_DIR/vendor/weavec0"
    if [[ ! -d "$BOOTSTRAP_DIR/.git" ]]; then
      log "fetching weavec0 $WEAVEC0_TAG from $WEAVEC0_REPO"
      mkdir -p "$(dirname "$BOOTSTRAP_DIR")"
      git clone --depth 1 --branch "$WEAVEC0_TAG" "$WEAVEC0_REPO" "$BOOTSTRAP_DIR"
    fi
  fi

  [[ -d "$BOOTSTRAP_DIR" ]] || fail "weavec0 source dir not found: $BOOTSTRAP_DIR"
  [[ -x "$BOOTSTRAP_DIR/build.sh" ]] || fail "weavec0 build.sh not found at $BOOTSTRAP_DIR/build.sh"

  if [[ ! -x "$BOOTSTRAP_DIR/weavec0" ]] || [[ ! -d "$BOOTSTRAP_DIR/build/bootstrap-tests/bc" ]]; then
    log "building weavec0 ($BOOTSTRAP_DIR)"
    ( cd "$BOOTSTRAP_DIR" && ./build.sh ) || fail "weavec0 build failed"
  fi

  BOOTSTRAP_BC_DIR="$BOOTSTRAP_DIR/build/bootstrap-tests/bc"
  WEAVEC0="$BOOTSTRAP_DIR/weavec0"
  [[ -x "$WEAVEC0" ]] || fail "weavec0 binary not built at $WEAVEC0"
  [[ -d "$BOOTSTRAP_BC_DIR" ]] || fail "weavec0 bitcode dir missing: $BOOTSTRAP_BC_DIR"
}

compile_module() {
  local compiler="$1"
  local output_dir="$2"
  local name="$3"
  local src="$SRC_DIR/${name}.wir"
  local ll="$output_dir/${name}.ll"

  [[ -f "$src" ]] || fail "missing source module: $src"

  log "compile src/$name.wir"
  "$compiler" "$src" "$ll"
  [[ -s "$ll" ]] || fail "compiler produced empty LLVM IR for $name"
}

build_compiler() {
  local compiler="$1"
  local compiler_name="$2"
  local src_ll_dir="$3"
  local link_ll_dir="$4"
  local output="$5"

  log "building $compiler_name"

  mkdir -p "$src_ll_dir" "$link_ll_dir"
  rm -f "$src_ll_dir"/*.ll "$link_ll_dir"/*.ll

  local llvm_modules=()
  local module
  for module in "${MODULES[@]}"; do
    compile_module "$compiler" "$src_ll_dir" "$module"
  done

  local all_decls="$BUILD_DIR/$compiler_name.decls.ll"
  {
    # Cross-module declarations for the C-runtime externs every module may
    # call. weavec0's per-module emission only places a `declare` line for
    # externs declared in that specific .wir module, so here we seed the
    # full set for the link step (matches weavec0's admitted extern subset).
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
        if (name in skip) {
          next
        }
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

    llvm_modules+=("$link_ll")
  done

  local bootstrap_bitcode=()
  for module in "${BOOTSTRAP_MODULES[@]}"; do
    local bc="$BOOTSTRAP_BC_DIR/${module}.bc"
    [[ -f "$bc" ]] || fail "missing bootstrap bitcode: $bc"
    bootstrap_bitcode+=("$bc")
  done

  log "link $compiler_name"
  clang "${llvm_modules[@]}" "${bootstrap_bitcode[@]}" \
    "$BOOTSTRAP_DIR/runtime.c" -o "$output"
}

build_weavec1() {
  build_compiler "$WEAVEC0" "weavec1" "$SRC_LL_DIR" "$LINK_LL_DIR" "$WEAVEC1"
}

build_weavec2() {
  build_compiler "$WEAVEC1" "weavec2" "$SRC2_LL_DIR" "$LINK2_LL_DIR" "$WEAVEC2"
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

  log "llvm-as test $name"
  llvm-as "$ll" -o "$bc"

  log "clang test $name"
  clang "$ll" -o "$exe"

  log "run test $name"
  set +e
  "$exe"
  local actual_exit=$?
  set -e

  if [[ "$actual_exit" != "$expected_exit" ]]; then
    printf '\n--- generated LLVM IR: %s ---\n' "$ll" >&2
    sed -n '1,220p' "$ll" >&2 || true
    printf '\n' >&2
    fail "$name: expected exit $expected_exit, got $actual_exit"
  fi

  log "compare test $name"
  if [[ ! -f "$expected_ll" ]]; then
    if (( REGEN_GOLDENS )); then
      cp "$ll" "$expected_ll"
      log "regen $name (new golden)"
    else
      fail "missing expected LLVM IR: $expected_ll (rerun with --regen-goldens to create)"
    fi
  elif ! diff -u "$expected_ll" "$ll" >/dev/null; then
    if (( REGEN_GOLDENS )); then
      cp "$ll" "$expected_ll"
      log "regen $name (updated golden)"
    else
      diff -u "$expected_ll" "$ll" || true
      fail "$name: generated LLVM IR differs from expected fixture (rerun with --regen-goldens to accept)"
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

  [[ -f "$src" ]] || fail "missing test source: $src"

  log "compile-fail test $name"
  rm -f "$ll" "$output"
  set +e
  "$compiler" "$src" "$ll" >"$output" 2>&1
  local compile_status=$?
  set -e

  if [[ "$compile_status" == 0 ]]; then
    printf '\n--- unexpected generated LLVM IR: %s ---\n' "$ll" >&2
    sed -n '1,120p' "$ll" >&2 || true
    printf '\n' >&2
    fail "$name: expected $compiler_name compiler failure, got success"
  fi

  if [[ -s "$ll" ]]; then
    printf '\n--- unexpected generated LLVM IR: %s ---\n' "$ll" >&2
    sed -n '1,120p' "$ll" >&2 || true
    printf '\n' >&2
    fail "$name: compiler failure still produced non-empty LLVM IR"
  fi

  if ! grep -q "$expected_message" "$output"; then
    printf '\n--- compiler output: %s ---\n' "$output" >&2
    sed -n '1,120p' "$output" >&2 || true
    printf '\n' >&2
    fail "$name: expected diagnostic containing: $expected_message"
  fi

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
      pass) run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "$name" "$rest" ;;
      fail) run_compile_fail_case "$compiler" "$compiler_name" "$test_ll_dir" "$name" "$rest" ;;
      *)    fail "unknown manifest entry kind: $kind (line: $line)" ;;
    esac
  done < "$MANIFEST"

  log "all $compiler_name tests passed"
}

compare_bootstrap_outputs() {
  log "comparing weavec1 vs weavec2 LLVM output for bootstrap determinism"

  local tests=(
    01_return_constant 02_return_42 03_add 04_one_arg_function
    05_let_local 06_set_local 07_if 08_while 09_two_arg_function
    10_string_literal 11_const_i64 12_i64_arithmetic 13_i64_comparisons
    14_bool_ops 15_ptr_null 16_extern_malloc_free 17_ptr_add_store_load_i64
    18_store_load_i8 19_call_void 20_call_i64 21_call_ptr 22_return_void
    23_mod_i32 24_buffer_like_smoke 25_ptr_params_call_i32 26_bool_return
    27_three_arg_function 28_i32_memory_and_cast 29_const_string_ptr
    30_i64_sub_eq 31_not_bool 32_codegen_join_and_i64_arg 33_store_i8_temp
    34_ge_i32 35_sub_i32 36_mul_i32 37_div_i32 38_i32_comparisons_full
    39_i64_ge_gt 40_call_bool_direct 41_load_store_ptr 42_empty_do
    43_if_fallthrough_join 44_while_zero_iterations 45_nested_while
    46_forward_function_call 47_multiple_externs_used_subset 48_string_escape
    49_negative_i32_literal 54_debug_marker
    55_integration_nested_control_flow 56_integration_multi_function_chain
    57_integration_memory_flow 60_empty_params_paren_list
  )

  local diverged=0
  local diverged_tests=()

  for test in "${tests[@]}"; do
    local weavec1_ll="$TEST_LL_DIR/${test}.ll"
    local weavec2_ll="$TEST2_LL_DIR/${test}.ll"

    if ! diff -u "$weavec1_ll" "$weavec2_ll" >/dev/null 2>&1; then
      printf '[bootstrap] DIVERGENCE: %s\n' "$test" >&2
      diff -u "$weavec1_ll" "$weavec2_ll" | head -50 >&2
      diverged=$((diverged + 1))
      diverged_tests+=("$test")
    fi
  done

  if [[ "$diverged" -gt 0 ]]; then
    printf '\n[bootstrap] ERROR: %d test(s) produced different LLVM IR between weavec1 and weavec2:\n' "$diverged" >&2
    for test in "${diverged_tests[@]}"; do
      printf '  - %s\n' "$test" >&2
    done
    printf '\nThis breaks the bootstrap determinism guarantee.\n' >&2
    printf 'weavec1 and weavec2 must produce identical LLVM IR.\n' >&2
    exit 1
  fi

  log "bootstrap determinism validated: weavec1 and weavec2 produce identical LLVM IR"
}

main() {
  require_tool clang
  require_tool llvm-as
  require_tool git
  ensure_weavec0
  build_weavec1
  run_tests "$WEAVEC1" "weavec1" "$TEST_LL_DIR" "$TEST_EXE_DIR"
  build_weavec2
  run_tests "$WEAVEC2" "weavec2" "$TEST2_LL_DIR" "$TEST2_EXE_DIR"
  compare_bootstrap_outputs
}

main "$@"
