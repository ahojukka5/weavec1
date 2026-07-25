#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Apply the reviewed Stage 1 unreachable-function removals exactly once."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REMOVALS = {
    ROOT / "src" / "emit_context.wir": {
        "ctx_local_count",
        "ctx_string_counter",
    },
    ROOT / "src" / "tokens.wir": {
        "token_else",
        "token_eq",
        "token_eqeq",
        "token_ge",
        "token_gt",
        "token_is",
        "token_is_eof",
        "token_le",
        "token_lt",
        "token_minus",
        "token_ne",
        "token_plus",
        "token_slash",
        "token_star",
    },
}
FN_RE = re.compile(r"^\s*\(fn\s+([A-Za-z_][A-Za-z0-9_-]*)\s*$")


def paren_delta(line: str) -> int:
    """Count structural parentheses while ignoring comments and strings."""

    delta = 0
    in_string = False
    escaped = False
    for ch in line:
        if not in_string and ch == ";":
            break
        if in_string:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
            continue
        if ch == '"':
            in_string = True
        elif ch == "(":
            delta += 1
        elif ch == ")":
            delta -= 1
    return delta


def comment_block_start(lines: list[str], fn_index: int) -> int:
    cursor = fn_index - 1
    while cursor >= 0 and lines[cursor].lstrip().startswith(";"):
        cursor -= 1
    if cursor >= 0 and not lines[cursor].strip():
        return cursor
    return cursor + 1


def remove_functions(path: Path, names: set[str]) -> None:
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    ranges: list[tuple[int, int, str]] = []

    for index, line in enumerate(lines):
        match = FN_RE.match(line.rstrip("\n"))
        if not match or match.group(1) not in names:
            continue
        name = match.group(1)
        depth = 0
        end = index
        for end in range(index, len(lines)):
            depth += paren_delta(lines[end])
            if depth == 0:
                end += 1
                break
        else:
            raise RuntimeError(f"{path}: unterminated function {name}")
        ranges.append((comment_block_start(lines, index), end, name))

    found = {name for _, _, name in ranges}
    missing = names - found
    if missing:
        remaining_text = "".join(lines)
        still_defined = {
            name for name in missing if re.search(rf"^\s*\(fn\s+{re.escape(name)}(?:\s|$)", remaining_text, re.M)
        }
        if still_defined:
            raise RuntimeError(f"{path}: failed to locate {sorted(still_defined)}")

    for start, end, _ in sorted(ranges, reverse=True):
        del lines[start:end]

    while any(
        lines[index].strip() == "" and lines[index - 1].strip() == ""
        for index in range(1, len(lines))
    ):
        lines = [
            line
            for index, line in enumerate(lines)
            if not (
                index > 0
                and line.strip() == ""
                and lines[index - 1].strip() == ""
            )
        ]

    path.write_text("".join(lines), encoding="utf-8")


def main() -> None:
    for path, names in REMOVALS.items():
        remove_functions(path, names)


if __name__ == "__main__":
    main()
