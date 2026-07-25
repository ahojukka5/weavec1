#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Validate the frozen Stage 1 WIR source inventory and source style."""

from __future__ import annotations

import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SRC_DIR = REPO_ROOT / "src"
BUILD_SCRIPT = REPO_ROOT / "build.sh"
FN_RE = re.compile(r"^\s*\(fn\s+([A-Za-z_][A-Za-z0-9_-]*)$")
OLD_FN_RE = re.compile(r"^\s*\(fn$")
PARAM_RE = re.compile(r"^\s*\(([A-Za-z_][A-Za-z0-9_]*)\s+([A-Za-z0-9_]+)\)+$")
RET_RE = re.compile(r"^\s*\(returns\s+([A-Za-z0-9_]+)\)$")
CORE_VERSION_RE = re.compile(r"^\s*\(core-version\s+([0-9]+)\)\s*$")
MODULE_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
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


def parse_build_modules() -> tuple[list[str], list[str]]:
    """Read the authoritative MODULES array from build.sh."""

    errors: list[str] = []
    modules: list[str] = []
    in_modules = False
    found_modules = False
    closed_modules = False

    for lineno, line in enumerate(BUILD_SCRIPT.read_text(encoding="utf-8").splitlines(), start=1):
        stripped = line.strip()
        if not in_modules:
            if stripped == "MODULES=(":
                in_modules = True
                found_modules = True
            continue

        if stripped == ")":
            closed_modules = True
            break
        if not stripped or stripped.startswith("#"):
            continue
        if not MODULE_RE.fullmatch(stripped):
            errors.append(
                f"build.sh:{lineno}: invalid MODULES entry `{stripped}`"
            )
            continue
        modules.append(stripped)

    if not found_modules:
        errors.append("build.sh: missing MODULES array")
    elif not closed_modules:
        errors.append("build.sh: unterminated MODULES array")

    seen: set[str] = set()
    for module in modules:
        if module in seen:
            errors.append(f"build.sh: duplicate MODULES entry `{module}`")
        seen.add(module)

    return modules, errors


def check_source_inventory(modules: list[str]) -> list[str]:
    """Require a one-to-one mapping between build modules and src/*.wir."""

    errors: list[str] = []
    expected = set(modules)
    actual = {path.stem for path in SRC_DIR.glob("*.wir")}

    for module in sorted(expected - actual):
        errors.append(f"build.sh: listed source module is missing: src/{module}.wir")
    for module in sorted(actual - expected):
        errors.append(f"src/{module}.wir: source module is not listed in build.sh MODULES")

    if not actual:
        errors.append("src: no WIR source modules found")

    return errors


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
    versions = [
        match.group(1)
        for line in lines
        if (match := CORE_VERSION_RE.match(line)) is not None
    ]
    if versions != ["2"]:
        rendered = ", ".join(versions) if versions else "none"
        errors.append(
            f"{rel}: expected exactly one `(core-version 2)`, found {rendered}"
        )

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
            else:
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
    modules, errors = parse_build_modules()
    errors.extend(check_source_inventory(modules))

    for path in sorted(SRC_DIR.glob("*.wir")):
        errors.extend(check_file(path))

    if errors:
        for error in errors:
            print(error)
        return 1

    print("WIR source inventory and style checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
