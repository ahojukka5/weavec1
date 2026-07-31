# Contributing to weavec1

`weavec1` is the WIR-written compiler stage between two versioned SDK
boundaries. It consumes the published Stage 0 SDK and publishes the compiler and
runtime consumed by `weavec-bootstrap`.

This repository is a stabilized bootstrap backend and should change
conservatively.

## Principles

- **Do not extend WIR casually.** WIR is the boundary shared with `weavec0`.
  Read [`docs/architecture.md`](docs/architecture.md) and
  [`docs/stabilization.md`](docs/stabilization.md).
- **No feature without a test.** Add every admitted shape to
  [`test/manifest.txt`](test/manifest.txt) and exercise it through
  `./build.sh`.
- **Bootstrap determinism is required.** `build/weavec1` and
  `build/weavec1-selfhost` must emit byte-identical LLVM output on positive
  fixtures.
- **SDK contracts are versioned.** Changes to compiler behavior, runtime ABI,
  archive layout, or required Stage 0 components must be documented and released
  in dependency order.
- **Source style matters.** Follow
  [`docs/source-style.md`](docs/source-style.md) and run
  `python3 scripts/check_wir_source_style.py`.
- **Documentation is checked.** Files under `docs/` use lowercase kebab-case
  names and local Markdown links must resolve.

## What does not belong here

- New high-level surface-language features. Those belong in
  [`weavec`](https://github.com/ahojukka5/weavec).
- Bootstrap surface-lowering changes. Those belong in
  [`weavec-bootstrap`](https://github.com/ahojukka5/weavec-bootstrap).
- Optimization, packages, advanced types, or IDE behavior.
- Uncoordinated changes to WIR or the runtime ABI.
- A runtime extern added only in Stage 1. Add it to `weavec0`, publish a new
  Stage 0 SDK, and then update `WEAVEC0_VERSION`.

## Development workflow

1. Create a focused branch.
2. Edit `src/*.wir`, tests, build tooling, or documentation.
3. Add new behavior to `test/manifest.txt`.
4. Run:

   ```sh
   python3 scripts/check_docs.py
   python3 scripts/check_wir_source_style.py
   python3 scripts/audit_wir_reachability.py
   ./build.sh
   ```

5. Regenerate and review goldens only after an intentional emitter change:

   ```sh
   ./build.sh --regen-goldens
   git diff -- test/
   ```

6. Confirm both compiler generations pass the same ladder and emit identical
   positive LLVM output.
7. Update README, changelog, architecture, stabilization, or release
   documentation when a public contract changes.
8. Open a focused pull request.

CI validates documentation and frozen-source audits, Linux x86-64 with glibc and
musl Stage 0 SDKs, and macOS with the source fallback. The release workflow
additionally builds and smoke-tests both Linux Stage 1 SDK variants and the
native macOS arm64 and x86_64 Stage 1 SDKs.

## SDK-affecting changes

For an output-SDK change:

1. update [`VERSION`](VERSION) intentionally;
2. validate both libc variants;
3. document compatibility and archive changes;
4. publish the Stage 1 SDK;
5. only then update the `WEAVEC1_VERSION` pin in `weavec-bootstrap`.

See [`docs/index.md`](docs/index.md) and
[`docs/releasing.md`](docs/releasing.md).

## Licensing

By submitting a contribution, you agree that it is licensed under the Apache
License, Version 2.0. See [`LICENSE`](LICENSE).
