# weavec1 — Weave Stage 1 Compiler

[![ci](https://github.com/ahojukka5/weavec1/actions/workflows/ci.yml/badge.svg)](https://github.com/ahojukka5/weavec1/actions/workflows/ci.yml)

> The second-stage Weave compiler. Written in WIR, compiled by
> [`weavec0`](https://github.com/ahojukka5/weavec0). Emits LLVM IR.

## Overview

`weavec1` is the first compiler in the Weave chain to be **written in
the Weave intermediate representation (WIR)** rather than in
hand-written LLVM IR. It is bootstrapped by `weavec0` (the Stage 0
seed compiler) and produces the same `.wir → .ll` translation that
`weavec0` does — but with a self-hosted implementation that can later
be compiled by itself (`weavec2`) and exhibit *bootstrap determinism*:
`weavec1` and `weavec2` must emit byte-identical LLVM IR on the shared
test surface. The build script verifies this every run.

Once `weavec2` is stable, the WIR contract freezes and `weavec1`
itself mostly freezes too. See
[`docs/STABILIZATION.md`](docs/STABILIZATION.md) and
[`docs/STABLE_CORE.md`](docs/STABLE_CORE.md) for the freeze contract.

---

## Prerequisites

`weavec1` builds with a standard LLVM toolchain plus `git`:

- `clang`, `llvm-as`, `llvm-link` — LLVM 14 or newer (opaque pointers).
- `git` — to fetch the pinned `weavec0` dependency on first build.
- `bash` 4 or newer.
- `python3` (optional, for `scripts/check_wir_source_style.py`).

Installation hints:

```sh
# Debian / Ubuntu
sudo apt-get install -y llvm clang git

# macOS (Homebrew)
brew install llvm git
export PATH="$(brew --prefix llvm)/bin:$PATH"
```

CI runs on `ubuntu-latest` and `macos-latest` against the
package-manager LLVMs.

---

## Quick start

```sh
git clone https://github.com/ahojukka5/weavec1.git
cd weavec1
./build.sh
```

**Note**: the first `./build.sh` is slower than subsequent runs — it
also clones and builds the pinned `weavec0` tag into
`build/vendor/weavec0/`. Re-runs reuse the cached vendor copy.

Inspect a tiny example and its emitted LLVM IR:

```sh
cat test/02_return_42.wir
cat test/02_return_42.expected.ll
```

---

## Repository layout

```text
weavec1/
  build.sh                    # build & ladder driver
  src/                        # WIR source modules (~30 files)
  test/                       # 60 ladder cases + manifest
    manifest.txt              # one line per case
    NN_<name>.wir             # positive case input
    NN_<name>.expected.ll     # golden output (regenerable)
  docs/                       # WIR contract, source style, fixtures
  scripts/
    check_wir_source_style.py # source style checker (heuristic)
  build/                      # gitignored
    vendor/weavec0/           # auto-fetched weavec0 dependency
    src-ll/, link-ll/,        # weavec1 compile artefacts
    src2-ll/, link2-ll/,      # weavec2 compile artefacts (self-host check)
    test-ll/, test-bin/,      # weavec1's ladder outputs
    test2-ll/                 # weavec2's ladder outputs
```

---

## Build

```sh
./build.sh                    # full build + ladder
./build.sh --regen-goldens    # accept golden updates after intentional change
```

Environment overrides:

- `WEAVEC0=/path/to/weavec0` — point at an existing weavec0 source
  tree that has already been built (where `./build.sh` produced
  `build/bootstrap-tests/bc/*.bc`). Skips the vendor fetch entirely.
- `WEAVEC0_TAG=vX.Y.Z` — change the pinned weavec0 tag (default
  `v0.2.0`). The build will re-clone if `build/vendor/weavec0/` was
  previously fetched at a different tag — delete the directory to
  force a refetch.

The script:

1. **Resolves weavec0** — either via `WEAVEC0` or by git-cloning
   `https://github.com/ahojukka5/weavec0` at `WEAVEC0_TAG` into
   `build/vendor/weavec0/` and running its `./build.sh`.
2. **Compiles weavec1** — every WIR module under `src/` is compiled
   by weavec0 to LLVM IR, augmented with cross-module declarations,
   then clang-linked with weavec0's compiled bitcode + runtime.c into
   the `weavec1` binary.
3. **Runs the ladder** — every case in `test/manifest.txt` is
   compiled by weavec1, the output diffed against the checked-in
   golden, and the resulting executable's exit code asserted.
4. **Compiles weavec2** — weavec1 compiles its own source to produce
   `weavec2`.
5. **Validates bootstrap determinism** — weavec1's and weavec2's
   per-test LLVM outputs must be byte-identical. A divergence is a
   hard error.

---

## Test ladder

`test/manifest.txt` enumerates **60 cases** (55 positive + 5
negative). Each positive case has two fixtures:

- `test/<name>.wir` — the WIR input.
- `test/<name>.expected.ll` — the golden LLVM IR.

A `.expected.ll` is a checked-in *golden* — the exact LLVM IR `weavec1`
produces today for the corresponding `.wir`. Goldens are regenerated
with `./build.sh --regen-goldens` and reviewed via `git diff` before
commit.

Per case the ladder checks, in this order:

1. `weavec1` compiles `.wir` → `.ll` without error.
2. The generated LLVM matches the golden fixture verbatim.
3. `llvm-as` accepts the generated LLVM.
4. `clang` builds an executable from it.
5. The executable's exit code matches the declared value.

Negative cases (`fail` rows in the manifest) instead check that
`weavec1` exits non-zero, writes no `.ll`, and emits a diagnostic
that contains a specified substring.

---

## Examples

Every file under [`test/`](test) is a runnable, end-to-end example.
Suggested entry points if you are reading the code for the first
time:

- [`test/01_return_constant.wir`](test/01_return_constant.wir) — the
  smallest possible WIR program.
- [`test/07_if.wir`](test/07_if.wir) — branching.
- [`test/08_while.wir`](test/08_while.wir) — loops and mutable locals.
- [`test/16_extern_malloc_free.wir`](test/16_extern_malloc_free.wir)
  — declaring and calling C externs.
- [`test/55_integration_nested_control_flow.wir`](test/55_integration_nested_control_flow.wir)
  — multi-feature integration test (nested control flow + i64).

---

## Where weavec1 fits in the chain

`weavec1` is the **middle stage** of a four-repository Weave compiler
chain. Each stage lives in its own repository and is independently
buildable.

| Stage | Repo | Role |
|-------|------|------|
| `weavec0` | [`ahojukka5/weavec0`](https://github.com/ahojukka5/weavec0) | Hand-written LLVM-IR seed compiler. Compiles WIR → LLVM IR. Tiny, frozen. |
| `weavec1` | **this repo** | WIR-written compiler. Compiled by `weavec0`. Same WIR → LLVM IR contract, self-hosted implementation. |
| `weavefront` | [`ahojukka5/weavefront`](https://github.com/ahojukka5/weavefront) | Surface (`.weave`) → WIR (`.wir`) frontend. Written in WIR, compiled by `weavec1`. |
| `weavec2` | [`ahojukka5/weavec2`](https://github.com/ahojukka5/weavec2) | Self-hosted Weave compiler. Written in surface Weave; bootstrapped via `weavefront + weavec1`. |

When `weavec2` is fully self-sustaining for surface inputs, both
`weavec1` and `weavefront` should mostly freeze. Future surface-level
compiler development moves to `weavec2`.

---

## Source style

WIR source modules under `src/` follow the conventions documented in
[`docs/WIR_SOURCE_STYLE.md`](docs/WIR_SOURCE_STYLE.md). Every function
gets a structured docstring with `Parameters:` and `Returns:` blocks.

A heuristic checker validates this:

```sh
python3 scripts/check_wir_source_style.py
```

Exit 0 if clean, non-zero with a list of violations otherwise. The
current source tree has some pre-existing style violations the checker
flags; cleaning them up is a follow-up task tracked separately.

---

## Known limitations

These are intentional scope choices and one open follow-up — not bugs.

- **WIR v1 is the frozen contract** between weavec0 and weavec1.
  Extending it requires coordinated changes across both repos and a
  versioned release of each. See
  [`docs/STABILIZATION.md`](docs/STABILIZATION.md).
- **Source semicolon (`;`) comments are not preserved** in emitted
  LLVM. The current lexer discards them before the parser can attach
  them to AST nodes. The emitter does inject its own `; section`
  banners, function-signature comments, and `(debug "...")` markers.
- **Tiny admitted extern subset** (inherited from weavec0): only
  `puts`, `malloc`, `free`, `realloc`, `memcpy`, `strlen`, `strcmp`,
  `strncmp`, `atoi`, `putchar`, `weave_rt_read_file`,
  `weave_rt_write_file`, `weave_rt_fatal`. Adding more requires a
  weavec0 release.
- **Blunt diagnostics** — short error strings, no source-position
  framework beyond `at line` for parse errors.
- **17 pre-existing style violations** flagged by
  `scripts/check_wir_source_style.py` (missing `Parameters:` /
  `Returns:` blocks on some functions, short doc blocks). The checker
  no longer crashes; cleaning the source is a follow-up.
- **The vendored weavec0 cache** at `build/vendor/weavec0/` is not
  auto-updated when `WEAVEC0_TAG` changes. Delete the directory and
  re-run `./build.sh` to refetch.

---

## License

Licensed under the Apache License, Version 2.0. See
[`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).

## Contributing

Pull requests and issues are welcome. The merge bar is intentionally
narrow — please read [`CONTRIBUTING.md`](CONTRIBUTING.md), the
**Known limitations** section above, and
[`docs/STABILIZATION.md`](docs/STABILIZATION.md) before opening a PR.
