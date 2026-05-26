# Contributing to weavec1

Thanks for your interest in `weavec1`. Before opening a PR or filing an
issue, please understand the very narrow scope: `weavec1` is the
**WIR-written** stage of the Weave compiler chain. It is compiled by
[`weavec0`](https://github.com/ahojukka5/weavec0) and exists to bridge
to `weavec2` (the surface-Weave compiler). Once the WIR contract is
frozen and `weavec2` is stable, `weavec1` itself should mostly freeze.

## Principles

- **No new WIR features in `weavec1`.** WIR is the boundary between
  weavec0 and weavec1; changing it ripples into both. See
  [`docs/STABILIZATION.md`](docs/STABILIZATION.md) and
  [`docs/STABLE_CORE.md`](docs/STABLE_CORE.md) for what is frozen.
- **No feature without a test.** A patch that adds an admitted shape
  must come with an entry in [`test/manifest.txt`](test/manifest.txt)
  exercising it end-to-end through `./build.sh`.
- **Bootstrap determinism is sacred.** weavec1 must emit byte-identical
  LLVM IR to weavec2 (the compiler weavec1 compiles). The build script
  verifies this; never accept a PR that produces a divergence.
- **Source style matters.** WIR source follows
  [`docs/WIR_SOURCE_STYLE.md`](docs/WIR_SOURCE_STYLE.md). Run the
  checker locally before submitting:
  ```sh
  python3 scripts/check_wir_source_style.py
  ```

## What does NOT belong here

- Anything that requires extending weavec0's admitted extern subset.
  If weavec1 needs a new C-runtime extern, the change goes to
  `weavec0` first, gets a tagged release, and then weavec1's
  `WEAVEC0_TAG` pin is bumped.
- Anything that breaks the WIR v1 contract.
- Optimisation, advanced types, packages, beautiful diagnostics —
  same non-goals as the rest of the Weave chain. Those belong to
  later compiler stages.

## Workflow

1. Fork and create a feature branch.
2. Edit the relevant `src/*.wir`, add or update a test under `test/`,
   and append the entry to `test/manifest.txt`.
3. Run `./build.sh` locally — full ladder must pass, including the
   weavec1↔weavec2 bootstrap determinism check.
4. If your change affects emitter output, rerun
   `./build.sh --regen-goldens` and commit the regenerated
   `.expected.ll` files alongside your source change.
5. Run the style checker (`python3 scripts/check_wir_source_style.py`)
   — your additions must not introduce new style violations.
6. Open a PR. CI re-runs the full ladder on Linux and macOS.

## Licensing

By submitting a contribution, you agree that your contribution is
licensed under the Apache License, Version 2.0 (see
[`LICENSE`](LICENSE)).
