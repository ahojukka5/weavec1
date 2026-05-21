#!/usr/bin/env python3
"""Heuristic WIR source documentation/style checker."""

from __future__ import annotations

import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SRC_DIR = REPO_ROOT / "src"
FN_RE = re.compile(r"^\s*\(fn\s+([A-Za-z_][A-Za-z0-9_-]*)$")
OLD_FN_RE = re.compile(r"^\s*\(fn$")
PARAM_RE = re.compile(r"^\s*\(([A-Za-z_][A-Za-z0-9_]*)\s+([A-Za-z0-9_]+)\)+$")
RET_RE = re.compile(r"^\s*\(returns\s+([A-Za-z0-9_]+)\)$")
BAD_DOC_PATTERNS = (
    "Provides ",
    "Implements ",
    "Emits or computes ",
    "Reads or computes ",
    "Handles ",
    "Documents the bootstrap helper",
    "result value",
    "field value or status code",
    "storage value",
)


def parse_signature(lines: list[str], index: int) -> tuple[str, list[str], str]:
    opener = FN_RE.match(lines[index])
    name = opener.group(1) if opener else ""
    params: list[str] = []
    returns = ""
    in_params = False

    for offset in range(index + 1, min(len(lines), index + 80)):
        stripped = lines[offset].strip()
        if stripped == "(params)":
            in_params = False
            continue
        if stripped == "(params":
            in_params = True
            continue
        if in_params and stripped == ")":
            in_params = False
            continue
        if in_params:
            match = PARAM_RE.match(stripped)
            if match:
                params.append(match.group(1))
            if stripped.endswith("))"):
                in_params = False
            continue
        match = RET_RE.match(stripped)
        if match:
            returns = match.group(1)
            break

    return name, params, returns


def preceding_comment_block(lines: list[str], index: int) -> tuple[int, list[str]]:
    cursor = index - 1
    if cursor >= 0 and lines[cursor].strip() == "":
        cursor -= 1

    end = cursor
    while cursor >= 0 and lines[cursor].lstrip().startswith(";"):
        cursor -= 1

    start = cursor + 1
    if end < start:
        return index, []
    return start, lines[start : end + 1]


def check_file(path: Path) -> list[str]:
    raw = path.read_bytes()
    rel = path.relative_to(REPO_ROOT)
    errors: list[str] = []

    if raw and not raw.endswith(b"\n"):
        errors.append(f"{rel}: file must end with newline")

    text = raw.decode("utf-8")
    lines = text.splitlines()

    for lineno, line in enumerate(lines, start=1):
        if line.rstrip() != line:
            errors.append(f"{rel}:{lineno}: trailing whitespace")

    for index, line in enumerate(lines):
        if OLD_FN_RE.match(line):
            errors.append(
                f"{rel}:{index + 1}: function opener must be `(fn name`"
            )
            continue
        if not FN_RE.match(line):
            continue

        fn_line = index + 1
        name, params, returns = parse_signature(lines, index)
        block_start, block = preceding_comment_block(lines, index)
        block_text = "\n".join(block)

        if not name:
            errors.append(f"{rel}:{fn_line}: unable to read function name")
            continue

        if not block:
            errors.append(f"{rel}:{fn_line}: missing documentation block for {name}")
            continue

        if len(block) < 6:
            errors.append(f"{rel}:{fn_line}: documentation block is too short")

        if block[0].strip() != ";":
            errors.append(f"{rel}:{block_start + 1}: documentation block must start with `;`")

        if len(block) < 2 or block[1].strip() != f"; {name}":
            errors.append(f"{rel}:{fn_line}: documentation block must name {name}")

        if block[-1].strip() != ";":
            errors.append(f"{rel}:{fn_line}: documentation block must end with `;`")

        for block_lineno, comment in enumerate(block, start=block_start + 1):
            for pattern in BAD_DOC_PATTERNS:
                if pattern in comment:
                    errors.append(
                        f"{rel}:{block_lineno}: generic documentation phrase `{pattern}`"
                    )

        if returns and "; Returns:" not in block:
            errors.append(f"{rel}:{fn_line}: {name} must document Returns")

        if params:
            if "; Parameters:" not in block:
                errors.append(f"{rel}:{fn_line}: {name} must document Parameters")
            for param in params:
                if not re.search(rf"^;\s+{re.escape(param)}\s+-", block_text, re.M):
                    errors.append(
                        f"{rel}:{fn_line}: {name} must document parameter {param}"
                    )

            param_index = block.index("; Parameters:")
            if param_index + 1 >= len(block) or block[param_index + 1].strip() == ";":
                errors.append(f"{rel}:{fn_line}: Parameters must list entries immediately")

        if block_start > 0 and lines[block_start - 1].strip() != "":
            errors.append(
                f"{rel}:{block_start + 1}: documentation block needs a leading blank line"
            )

        if index > 0 and lines[index - 1].strip() == "":
            errors.append(f"{rel}:{fn_line}: docs must attach directly to function")

    return errors


def main() -> int:
    errors: list[str] = []
    for path in sorted(SRC_DIR.glob("*.wir")):
        errors.extend(check_file(path))

    if errors:
        for error in errors:
            print(error)
        return 1

    print("WIR source style checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
