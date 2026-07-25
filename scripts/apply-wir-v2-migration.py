#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text()


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text)


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1, got {count}")
    return text.replace(old, new, 1)


# Migrate all compiler and test WIR sources to the new contract.
for path in sorted((ROOT / "src").glob("*.wir")) + sorted((ROOT / "test").glob("*.wir")):
    source = path.read_text()
    if "(core-version 1)" in source:
        path.write_text(source.replace("(core-version 1)", "(core-version 2)"))

# The compiler itself must require v2 and report v2 in emitted LLVM headers.
path = "src/parser_decl.wir"
text = read(path)
text = replace_once(
    text,
    """            (ne_i32
              (local_get version)
              (const_i32 1)))""",
    """            (ne_i32
              (local_get version)
              (const_i32 2)))""",
    "parser version check",
)
write(path, text)

path = "src/emit_sections.wir"
write(path, replace_once(
    read(path),
    '(const_string_ptr "; core-version: 1")',
    '(const_string_ptr "; core-version: 2")',
    "emitted version header",
))

for path in sorted((ROOT / "test").glob("*.expected.ll")):
    path.write_text(path.read_text().replace("; core-version: 1", "; core-version: 2"))

# Old contract rejection is an explicit regression.
write("test/62_core_version_1_rejected.wir", """; 62_core_version_1_rejected.wir
; purpose: rejects the superseded WIR core version 1 contract.

(core-module
  (core-version 1)
  (decls
    (fn main
      (params)
      (returns i32)
      (do
        (return
          (const_i32 0)))))))
""")
manifest = read("test/manifest.txt")
anchor = "fail 61_parse_error_location                  at line\n"
manifest = replace_once(
    manifest,
    anchor,
    anchor + "fail 62_core_version_1_rejected              parse failed\n",
    "manifest v1 rejection",
)
write("test/manifest.txt", manifest)

# Dependency and release versions.
for path in [
    "build.sh",
    "scripts/package-linux-sdk.sh",
    ".github/workflows/ci.yml",
    ".github/workflows/release.yml",
]:
    write(path, read(path).replace("v0.2.1", "v0.4.0"))
write("VERSION", "0.3.0\n")

# README: replace the dependency section and current release references.
readme = read("README.md")
readme = readme.replace("weavec0 v0.2.1 SDK", "weavec0 v0.4.0 SDK")
readme = readme.replace("weavec1 v0.2.0 SDK", "weavec1 v0.3.0 SDK")
readme = readme.replace(
    "Release `v0.2.0` introduced static Linux x86-64 SDKs for glibc and musl:",
    "Release `v0.3.0` publishes static Linux x86-64 SDKs for glibc and musl:",
)
readme = readme.replace(
    "`test/manifest.txt` contains 60 cases: 55 positive and 5 expected failures.",
    "`test/manifest.txt` contains 60 cases: 54 positive and 6 expected failures.",
)
readme = readme.replace(
    "- WIR v1 is the stable boundary between Stage 0 and Stage 1.",
    "- WIR core version 2 is the stable boundary between Stage 0 and Stage 1.",
)
start = readme.index("## Stage 0 dependency")
end = readme.index("## Build pipeline")
new_section = """## Stage 0 dependency

The default dependency is `weavec0 v0.4.0`. Stage 1 requires only:

```text
bin/weavec0
lib/libweavec0-runtime.a
```

`bin/weavec0` is a build-time compiler: it translates the Stage 1 WIR v2
modules to LLVM IR. The resulting Stage 1 binaries contain only the generated
Stage 1 modules and the matching runtime implementation. They do not link or
embed the Stage 0 compiler implementation.

Environment overrides:

- `WEAVEC0_VERSION=v0.4.0` selects the published SDK;
- `WEAVEC0_LIBC=glibc|musl` selects the Linux variant;
- `WEAVEC0_SDK=/path/to/sdk` uses an extracted SDK;
- `WEAVEC0_RELEASE_BASE=<url>` changes the release base;
- `WEAVEC0=/path/to/source` selects a built source tree;
- `WEAVEC0_TAG=v0.4.0` selects the source-fallback tag.

"""
write("README.md", readme[:start] + new_section + readme[end:])

# Stable contract documentation.
write("docs/STABLE_CORE.md", """# Stable WIR Core Architecture

This document defines the backend contract shared by the Weave bootstrap
compiler chain.

## WIR core version 2

WIR is the typed, deterministic boundary between surface lowering and LLVM
emission:

```lisp
(core-module
  (core-version 2)
  (decls
    (fn main
      (params)
      (returns i32)
      (do
        (return (const_i32 42))))))
```

Core version 2 is small, explicit, close to LLVM semantics, human-readable, and
versioned conservatively. Core version 1 remains reproducible through immutable
older compiler releases; current compilers reject it.

## Compiler chain

```text
weavec0 → weavec1 → weavec-bootstrap → weavec
```

| Component | Role |
|---|---|
| [`weavec0`](https://github.com/ahojukka5/weavec0) | Hand-written LLVM-IR seed. Implements only the WIR v2 bootstrap profile required to compile `weavec1`. |
| `weavec1` | WIR-written backend. Implements the complete stable WIR v2 backend and publishes the Stage 1 SDK. |
| [`weavec-bootstrap`](https://github.com/ahojukka5/weavec-bootstrap) | Deterministic surface-Weave-to-WIR bootstrap frontend. |
| [`weavec`](https://github.com/ahojukka5/weavec) | User-facing self-hosted compiler. |

The Stage 0 bootstrap profile is intentionally a strict implementation subset:
it accepts exactly the forms used by the pinned Stage 1 source modules. This is
not a second language version. Stage 1 owns the complete backend surface used by
downstream compilers.

## Bootstrap determinism

`build.sh` builds `weavec1` with `weavec0`, rebuilds the same compiler with the
first generation, runs the complete positive and negative ladder through both,
and requires byte-identical LLVM output. Any divergence is a build failure.

## Stable backend contract

WIR core version 2 includes explicit scalar and pointer types, arithmetic and
comparisons, memory operations, locals and parameters, typed calls and externs,
structured control flow, string pointer constants, and module declarations.
The authoritative admitted shapes are the Stage 1 implementation and fixtures
under `test/`.

Allowed changes without a new core version are correctness fixes, deterministic
implementation improvements, diagnostics, tests, and packaging changes that
preserve semantics. Removing or changing an admitted form, changing its type or
semantics, breaking valid v2 programs, or changing the runtime ABI incompatibly
requires a new core version and coordinated release.

## Runtime and SDK boundaries

Stage 1 consumes the minimal Stage 0 SDK:

```text
bin/weavec0
lib/libweavec0-runtime.a
include/runtime.h
```

Stage 1 publishes:

```text
bin/weavec1
lib/libweave-runtime.a
include/runtime.h
```

Downstream pins move only after the corresponding upstream release and checksums
exist.

## Verification

Run `./build.sh`. A passing build confirms the Stage 0 SDK can build Stage 1,
the full WIR v2 ladder passes, the second generation rebuilds the compiler, and
both generations emit identical output.
""")

write("docs/STABILIZATION.md", """# WIR Core Stabilization

This document records the stabilized WIR core version 2 and Stage 0/Stage 1
bootstrap boundary.

## Current chain

```text
weavec0 → weavec1 → weavec-bootstrap → weavec
```

`weavec0` is the minimal hand-written seed. `weavec1` is the WIR-written backend
and complete stable-core implementation. The upper stages lower surface Weave to
WIR and provide the user-facing compiler.

## Stabilized guarantees

- `build.sh` builds two consecutive Stage 1 generations.
- Both generations run the same positive and negative ladder.
- Every positive LLVM fixture is compared byte for byte.
- LLVM assembly, native linking, runtime exit codes, SDK contents, and checksums
  are validated.
- Linux builds consume `weavec0 v0.4.0`; `weavec1 v0.3.0` publishes the matching
  Stage 1 SDK.

## Version 2 boundary

WIR v2 stabilizes `(core-module (core-version 2) ...)`, the admitted types and
operators, deterministic WIR-to-LLVM emission, and the runtime ABI. Current
compilers reject core version 1; immutable older releases retain that contract.

Stage 0 deliberately implements only the bootstrap profile exercised by the
pinned `weavec1` source modules. Stage 1 implements the complete stable v2
backend. Expanding Stage 0 merely to match Stage 1 is not a goal.

Without a new WIR version, changes are limited to bug fixes, deterministic
internal improvements, clearer diagnostics, tests, and compatible SDK packaging.
Changing semantics, removing admitted Stage 1 forms, breaking valid v2 programs,
or changing the runtime ABI incompatibly requires coordinated versioning.

## Dependency release order

1. release `weavec0`;
2. update, validate, and release `weavec1`;
3. update `weavec-bootstrap`;
4. update and self-host `weavec`.

Downstream pins never move before upstream assets and `SHA256SUMS` exist.

## Verification

`./build.sh` verifies Stage 0 acquisition, first-generation construction, the
complete ladder, second-generation construction, and byte-identical output.
""")

write("docs/RELEASING.md", read("docs/RELEASING.md").replace("v0.2.0", "v0.3.0"))

# Changelog: retain the previous unreleased changes in the same 0.3.0 section.
changelog = read("CHANGELOG.md")
marker = "## [Unreleased]\n"
if not changelog.startswith("# Changelog") or marker not in changelog:
    raise SystemExit("unexpected changelog layout")
changelog = changelog.replace(marker, """## [Unreleased]

## [0.3.0] — 2026-07-25

### Added

- A regression proving the superseded core version 1 contract is rejected.
- Documentation of the distinction between the minimal Stage 0 bootstrap
  profile and the complete Stage 1 WIR v2 backend.

### Changed

- Migrated all Stage 1 source modules and fixtures to WIR core version 2.
- The compiler now requires core version 2 and emits `; core-version: 2`.
- The default Stage 0 dependency is `weavec0 v0.4.0`.
- Bumped the Stage 1 SDK version to 0.3.0.
""", 1)
changelog = changelog.replace(
    "- Bumped the Stage 1 SDK version to 0.3.0.\n\n### Changed\n\n- Renamed",
    "- Bumped the Stage 1 SDK version to 0.3.0.\n- Renamed",
    1,
)
write("CHANGELOG.md", changelog)

# Contract assertions.
for path in sorted((ROOT / "src").glob("*.wir")):
    if "(core-version 1)" in path.read_text():
        raise SystemExit(f"v1 remains in source: {path}")
for path in sorted((ROOT / "test").glob("*.wir")):
    if path.name != "62_core_version_1_rejected.wir" and "(core-version 1)" in path.read_text():
        raise SystemExit(f"v1 remains in test: {path}")
for path in sorted((ROOT / "test").glob("*.expected.ll")):
    if "; core-version: 1" in path.read_text():
        raise SystemExit(f"v1 remains in golden: {path}")
for path in [
    "build.sh",
    "scripts/package-linux-sdk.sh",
    ".github/workflows/ci.yml",
    ".github/workflows/release.yml",
]:
    if "v0.2.1" in read(path):
        raise SystemExit(f"old Stage 0 dependency remains: {path}")

print("migrated weavec1 to WIR v2")
