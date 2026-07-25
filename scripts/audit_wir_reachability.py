#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Audit reachability of the frozen weavec1 WIR implementation."""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import TypeAlias


REPO_ROOT = Path(__file__).resolve().parents[1]
SRC_DIR = REPO_ROOT / "src"
DEFAULT_REPORT = REPO_ROOT / "build" / "audit" / "weavec1-reachability.json"
CALL_FORMS = {"call_bool", "call_i32", "call_i64", "call_ptr", "call_void"}


@dataclass(frozen=True)
class StringLiteral:
    value: str


SExpr: TypeAlias = str | StringLiteral | list["SExpr"]


class ParseError(ValueError):
    pass


def tokenize(text: str, path: Path) -> list[str | StringLiteral]:
    tokens: list[str | StringLiteral] = []
    index = 0
    line = 1

    while index < len(text):
        ch = text[index]
        if ch in " \t\r":
            index += 1
            continue
        if ch == "\n":
            line += 1
            index += 1
            continue
        if ch == ";":
            newline = text.find("\n", index)
            if newline == -1:
                break
            index = newline
            continue
        if ch in "()":
            tokens.append(ch)
            index += 1
            continue
        if ch == '"':
            start_line = line
            index += 1
            chars: list[str] = []
            while index < len(text):
                ch = text[index]
                if ch == '"':
                    index += 1
                    tokens.append(StringLiteral("".join(chars)))
                    break
                if ch == "\\":
                    index += 1
                    if index >= len(text):
                        raise ParseError(f"{path}:{start_line}: unterminated string escape")
                    escaped = text[index]
                    chars.append("\\")
                    chars.append(escaped)
                    index += 1
                    continue
                if ch == "\n":
                    line += 1
                chars.append(ch)
                index += 1
            else:
                raise ParseError(f"{path}:{start_line}: unterminated string literal")
            continue

        start = index
        while index < len(text) and text[index] not in "()\"; \t\r\n":
            index += 1
        if start == index:
            raise ParseError(f"{path}:{line}: unexpected byte {text[index]!r}")
        tokens.append(text[start:index])

    return tokens


def parse_forms(tokens: list[str | StringLiteral], path: Path) -> list[SExpr]:
    forms: list[SExpr] = []
    index = 0

    def parse_one() -> SExpr:
        nonlocal index
        if index >= len(tokens):
            raise ParseError(f"{path}: unexpected end of file")
        token = tokens[index]
        index += 1
        if token == "(":
            items: list[SExpr] = []
            while True:
                if index >= len(tokens):
                    raise ParseError(f"{path}: unterminated list")
                if tokens[index] == ")":
                    index += 1
                    return items
                items.append(parse_one())
        if token == ")":
            raise ParseError(f"{path}: unexpected `)`")
        return token

    while index < len(tokens):
        forms.append(parse_one())
    return forms


def walk(node: SExpr):
    yield node
    if isinstance(node, list):
        for child in node:
            yield from walk(child)


def collect_declarations(
    forms_by_file: dict[Path, list[SExpr]],
) -> tuple[dict[str, tuple[Path, list[SExpr]]], set[str], list[str]]:
    functions: dict[str, tuple[Path, list[SExpr]]] = {}
    externs: set[str] = set()
    errors: list[str] = []

    for path, forms in forms_by_file.items():
        for form in forms:
            for node in walk(form):
                if not isinstance(node, list) or len(node) < 2:
                    continue
                head, name = node[0], node[1]
                if head not in {"fn", "extern"} or not isinstance(name, str):
                    continue
                if head == "extern":
                    externs.add(name)
                    continue
                previous = functions.get(name)
                if previous is not None:
                    errors.append(
                        f"duplicate function `{name}` in {path.relative_to(REPO_ROOT)} "
                        f"and {previous[0].relative_to(REPO_ROOT)}"
                    )
                    continue
                functions[name] = (path, node)

    return functions, externs, errors


def direct_calls(function: list[SExpr]) -> set[str]:
    calls: set[str] = set()
    for node in walk(function):
        if not isinstance(node, list) or len(node) < 2:
            continue
        head, target = node[0], node[1]
        if head in CALL_FORMS and isinstance(target, str):
            calls.add(target)
    return calls


def audit(report_path: Path) -> int:
    forms_by_file: dict[Path, list[SExpr]] = {}
    errors: list[str] = []

    for path in sorted(SRC_DIR.glob("*.wir")):
        try:
            forms_by_file[path] = parse_forms(
                tokenize(path.read_text(encoding="utf-8"), path), path
            )
        except (OSError, UnicodeError, ParseError) as exc:
            errors.append(str(exc))

    functions, externs, declaration_errors = collect_declarations(forms_by_file)
    errors.extend(declaration_errors)

    roots = {"main"}
    missing_roots = sorted(roots - functions.keys())
    if missing_roots:
        errors.extend(f"missing reachability root `{name}`" for name in missing_roots)

    graph = {name: direct_calls(node) for name, (_, node) in functions.items()}
    unresolved: dict[str, list[str]] = {}
    for caller, targets in graph.items():
        missing = sorted(targets - functions.keys() - externs)
        if missing:
            unresolved[caller] = missing
            errors.extend(
                f"{caller}: unresolved call target `{target}`" for target in missing
            )

    reachable: set[str] = set()
    pending = list(sorted(roots & functions.keys()))
    while pending:
        name = pending.pop()
        if name in reachable:
            continue
        reachable.add(name)
        pending.extend(sorted((graph[name] & functions.keys()) - reachable))

    unreachable = sorted(functions.keys() - reachable)
    for name in unreachable:
        path = functions[name][0].relative_to(REPO_ROOT)
        errors.append(f"{path}: unreachable source function `{name}`")

    called_targets = set().union(*graph.values()) if graph else set()
    unused_externs = sorted(externs - called_targets)
    for name in unused_externs:
        errors.append(f"unused source extern `{name}`")

    report = {
        "format": "weavec1-reachability-v1",
        "roots": sorted(roots),
        "source_files": len(forms_by_file),
        "function_count": len(functions),
        "extern_count": len(externs),
        "reachable_count": len(reachable),
        "unreachable": unreachable,
        "unresolved_calls": unresolved,
        "unused_externs": unused_externs,
        "functions": [
            {
                "name": name,
                "file": str(path.relative_to(REPO_ROOT)),
                "reachable": name in reachable,
                "calls": sorted(graph[name]),
            }
            for name, (path, _) in sorted(functions.items())
        ],
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )

    if errors:
        for error in errors:
            print(error)
        print(f"reachability report: {report_path.relative_to(REPO_ROOT)}")
        return 1

    print(
        f"WIR reachability passed: {len(reachable)}/{len(functions)} functions "
        f"reachable from main; {len(externs)} externs used."
    )
    print(f"reachability report: {report_path.relative_to(REPO_ROOT)}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()
    report = args.report
    if not report.is_absolute():
        report = REPO_ROOT / report
    return audit(report)


if __name__ == "__main__":
    sys.exit(main())
