#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Weave Stage 1 Bootstrap Build
# weave/weavec1/build.sh
#
# Build the WIR-written compiler with the hand-written LLVM Stage 0 compiler,
# then run the same curated WIR test ladder through the produced weavec1 binary.
# =============================================================================

WEAVEC1_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEAVE_DIR="$(cd "$WEAVEC1_DIR/.." && pwd)"
BOOTSTRAP_DIR="$WEAVE_DIR/src-bootstrap-llvm"
SRC_DIR="$WEAVEC1_DIR/src"
TEST_DIR="$WEAVEC1_DIR/tests"
BUILD_DIR="$WEAVEC1_DIR/build"
SRC_LL_DIR="$BUILD_DIR/src-ll"
LINK_LL_DIR="$BUILD_DIR/link-ll"
TEST_LL_DIR="$BUILD_DIR/test-ll"
TEST_EXE_DIR="$BUILD_DIR/test-bin"
BOOTSTRAP_BC_DIR="$BOOTSTRAP_DIR/build/bootstrap-tests/bc"

WEAVEC0="$BOOTSTRAP_DIR/weavec0"
WEAVEC1="$BUILD_DIR/weavec1"

MODULES=(
  runtime_bindings
  strings
  tokens
  ast
  lexer
  parser
  emit_llvm
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

log() {
  printf '[weavec1] %s\n' "$*"
}

fail() {
  printf '[weavec1] error: %s\n' "$*" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "required tool not found: $1"
}

build_weavec0() {
  log "building weavec0"
  "$BOOTSTRAP_DIR/build.sh"
}

compile_module() {
  local name="$1"
  local src="$SRC_DIR/${name}.wir"
  local ll="$SRC_LL_DIR/${name}.ll"

  [[ -f "$src" ]] || fail "missing source module: $src"

  log "compile src/$name.wir"
  "$WEAVEC0" "$src" "$ll"
  [[ -s "$ll" ]] || fail "compiler produced empty LLVM IR for $name"
}

build_weavec1() {
  log "building weavec1"

  mkdir -p "$SRC_LL_DIR" "$LINK_LL_DIR" "$TEST_LL_DIR" "$TEST_EXE_DIR"
  rm -f "$SRC_LL_DIR"/*.ll "$LINK_LL_DIR"/*.ll

  local llvm_modules=()
  local module
  for module in "${MODULES[@]}"; do
    compile_module "$module"
  done

  local all_decls="$BUILD_DIR/weavec1.decls.ll"
  {
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
      ' "$SRC_LL_DIR/${module}.ll"
    done
  } > "$all_decls"

  for module in "${MODULES[@]}"; do
    local src_ll="$SRC_LL_DIR/${module}.ll"
    local link_ll="$LINK_LL_DIR/${module}.ll"
    local names="$BUILD_DIR/${module}.names"
    local decls="$BUILD_DIR/${module}.decls.ll"

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

  log "link weavec1"
  clang "${llvm_modules[@]}" "${bootstrap_bitcode[@]}" \
    "$BOOTSTRAP_DIR/runtime.c" -o "$WEAVEC1"
}

run_case() {
  local name="$1"
  local expected_exit="$2"

  local src="$TEST_DIR/${name}.wir"
  local ll="$TEST_LL_DIR/${name}.ll"
  local exe="$TEST_EXE_DIR/${name}.out"

  [[ -f "$src" ]] || fail "missing test source: $src"

  log "compile test $name"
  "$WEAVEC1" "$src" "$ll"
  [[ -s "$ll" ]] || fail "weavec1 produced empty LLVM IR for $name"

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

  log "ok $name"
}

run_tests() {
  run_case "01_return_constant" 0
  run_case "02_return_42" 42
  run_case "03_add" 42
  run_case "04_one_arg_function" 42
  run_case "05_let_local" 42
  run_case "06_set_local" 42
  run_case "07_if" 42
  run_case "08_while" 42
  run_case "09_two_arg_function" 42
  run_case "10_string_literal" 42
  run_case "11_const_i64" 42
  run_case "12_i64_arithmetic" 42
  run_case "13_i64_comparisons" 42
  run_case "14_bool_ops" 42
  run_case "15_ptr_null" 42
  run_case "16_extern_malloc_free" 42
  run_case "17_ptr_add_store_load_i64" 42
  run_case "18_store_load_i8" 42
  run_case "19_call_void" 42
  run_case "20_call_i64" 42
  run_case "21_call_ptr" 42
  run_case "22_return_void" 42
  run_case "23_mod_i32" 2
  run_case "24_buffer_like_smoke" 42
  run_case "25_ptr_params_call_i32" 42
  run_case "26_bool_return" 42
  run_case "27_three_arg_function" 42
  run_case "28_i32_memory_and_cast" 42
  run_case "29_const_string_ptr" 42
  run_case "30_i64_sub_eq" 42
  run_case "31_not_bool" 42
  run_case "32_codegen_join_and_i64_arg" 42
  run_case "33_store_i8_temp" 42

  log "all weavec1 tests passed"
}

main() {
  require_tool clang
  build_weavec0
  build_weavec1
  run_tests
}

main "$@"
