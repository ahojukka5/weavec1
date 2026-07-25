#!/usr/bin/env python3
"""Patch a disposable checkout to test linking weavec1 without Stage 0 code."""
from __future__ import annotations

from pathlib import Path


def replace_once(text: str, old: str, new: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected one build.sh fragment, found {count}:\n{old}")
    return text.replace(old, new, 1)


def main() -> int:
    path = Path(__file__).resolve().parents[1] / "build.sh"
    text = path.read_text(encoding="utf-8")

    text = replace_once(
        text,
        '''  [[ -s "$sdk/lib/weavec0-bootstrap.o" ]] || \\
    fail "SDK bootstrap object missing: $sdk/lib/weavec0-bootstrap.o"
''',
        "",
    )
    text = replace_once(
        text,
        '''  BOOTSTRAP_OBJECT="$sdk/lib/weavec0-bootstrap.o"
''',
        "",
    )
    text = replace_once(
        text,
        '''      clang -static "${objects[@]}" "$BOOTSTRAP_OBJECT" \\
        "$BOOTSTRAP_RUNTIME_LIBRARY" -o "$output"
''',
        '''      clang -static "${objects[@]}" \\
        "$BOOTSTRAP_RUNTIME_LIBRARY" -o "$output"
''',
    )
    text = replace_once(
        text,
        '''      musl-gcc -static "${objects[@]}" "$BOOTSTRAP_OBJECT" \\
        "$BOOTSTRAP_RUNTIME_LIBRARY" -o "$output"
''',
        '''      musl-gcc -static "${objects[@]}" \\
        "$BOOTSTRAP_RUNTIME_LIBRARY" -o "$output"
''',
    )
    text = replace_once(
        text,
        '''  local bootstrap_bitcode=()
  for module in "${BOOTSTRAP_MODULES[@]}"; do
    local bc="$BOOTSTRAP_BC_DIR/${module}.bc"
    [[ -f "$bc" ]] || fail "missing bootstrap bitcode: $bc"
    bootstrap_bitcode+=("$bc")
  done

''',
        "",
    )
    text = replace_once(
        text,
        '''  clang "${llvm_modules[@]}" "${bootstrap_bitcode[@]}" \\
    "$BOOTSTRAP_DIR/runtime.c" -o "$output"
''',
        '''  clang "${llvm_modules[@]}" \\
    "$BOOTSTRAP_DIR/runtime.c" -o "$output"
''',
    )

    path.write_text(text, encoding="utf-8")
    print("patched build.sh to omit weavec0 bootstrap object and bitcode")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
