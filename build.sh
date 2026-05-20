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
SRC2_LL_DIR="$BUILD_DIR/src2-ll"
LINK_LL_DIR="$BUILD_DIR/link-ll"
LINK2_LL_DIR="$BUILD_DIR/link2-ll"
TEST_LL_DIR="$BUILD_DIR/test-ll"
TEST2_LL_DIR="$BUILD_DIR/test2-ll"
TEST_EXE_DIR="$BUILD_DIR/test-bin"
TEST2_EXE_DIR="$BUILD_DIR/test2-bin"
BOOTSTRAP_BC_DIR="$BOOTSTRAP_DIR/build/bootstrap-tests/bc"

WEAVEC0="$BOOTSTRAP_DIR/weavec0"
WEAVEC1="$BUILD_DIR/weavec1"
WEAVEC2="$BUILD_DIR/weavec2"

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

  local src="$TEST_DIR/${name}.wir"
  local expected_ll="$TEST_DIR/${name}.expected.ll"
  local ll="$test_ll_dir/${name}.ll"
  local bc="$test_ll_dir/${name}.bc"
  local exe="$test_exe_dir/${name}.out"

  [[ -f "$src" ]] || fail "missing test source: $src"
  [[ -f "$expected_ll" ]] || fail "missing expected LLVM IR: $expected_ll"

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
  if ! diff -u "$expected_ll" "$ll"; then
    fail "$name: generated LLVM IR differs from expected fixture"
  fi

  log "ok $name"
}

run_compile_fail_case() {
  local compiler="$1"
  local compiler_name="$2"
  local test_ll_dir="$3"
  local name="$4"
  local expected_message="$5"

  local src="$TEST_DIR/${name}.wir"
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

  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "01_return_constant" 0
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "02_return_42" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "03_add" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "04_one_arg_function" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "05_let_local" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "06_set_local" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "07_if" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "08_while" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "09_two_arg_function" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "10_string_literal" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "11_const_i64" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "12_i64_arithmetic" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "13_i64_comparisons" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "14_bool_ops" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "15_ptr_null" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "16_extern_malloc_free" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "17_ptr_add_store_load_i64" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "18_store_load_i8" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "19_call_void" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "20_call_i64" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "21_call_ptr" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "22_return_void" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "23_mod_i32" 2
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "24_buffer_like_smoke" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "25_ptr_params_call_i32" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "26_bool_return" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "27_three_arg_function" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "28_i32_memory_and_cast" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "29_const_string_ptr" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "30_i64_sub_eq" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "31_not_bool" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "32_codegen_join_and_i64_arg" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "33_store_i8_temp" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "34_ge_i32" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "35_sub_i32" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "36_mul_i32" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "37_div_i32" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "38_i32_comparisons_full" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "39_i64_ge_gt" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "40_call_bool_direct" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "41_load_store_ptr" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "42_empty_do" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "43_if_fallthrough_join" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "44_while_zero_iterations" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "45_nested_while" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "46_forward_function_call" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "47_multiple_externs_used_subset" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "48_string_escape" 42
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "49_negative_i32_literal" 42
  run_compile_fail_case "$compiler" "$compiler_name" "$test_ll_dir" "50_parse_error_smoke" "parse failed"
  run_compile_fail_case "$compiler" "$compiler_name" "$test_ll_dir" "51_unknown_operator" "unknown operator"
  run_compile_fail_case "$compiler" "$compiler_name" "$test_ll_dir" "52_wrong_arity_add_i32_too_few" "arity"
  run_compile_fail_case "$compiler" "$compiler_name" "$test_ll_dir" "53_wrong_arity_add_i32_too_many" "arity"
  run_case "$compiler" "$compiler_name" "$test_ll_dir" "$test_exe_dir" "54_debug_marker" 42

  log "all $compiler_name tests passed"
}

main() {
  require_tool clang
  require_tool llvm-as
  build_weavec0
  build_weavec1
  run_tests "$WEAVEC1" "weavec1" "$TEST_LL_DIR" "$TEST_EXE_DIR"
  build_weavec2
  run_tests "$WEAVEC2" "weavec2" "$TEST2_LL_DIR" "$TEST2_EXE_DIR"
}

main "$@"
