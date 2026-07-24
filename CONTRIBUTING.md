# Contributing to weavec1

`weavec1` is the WIR-written compiler stage between two versioned SDK
boundaries. It consumes the published Stage 0 SDK and publishes the compiler and
runtime consumed by `weavec-bootstrap`.

Once the WIR and surface bootstrap chain are stable, this repository should
change conservatively.

## Principles

- **Do not extend WIR casually.** WIR is the boundary shared with `weavec0`.
  Read [`docs/STABILIZATION.md`](docs/STABILIZATION.md) and
  [`docs/STABLE_CORE.md`](docs/STABLE_CORE.md).
- **No feature without a test.** Add every admitted shape to
  [`test/manifest.txt`](test/manifest.txt) and exercise it through
  `./build.sh`.
- **Bootstrap determinism is required.** `build/weavec1` and the second Stage 1
  generation must emit byte-identical LLVM output on positive fixtures. The
  latter currently uses the historical compatibility path `build/weavec1-selfhost`.
- **SDK contracts are versioned.** Changes to compiler behavior, runtime ABI,
  archive layout, or required Stage 0 components must be documented and
  released in dependency order.
- **Source style matters.** Follow
  [`docs/WIR_SOURCE_STYLE.md`](docs/WIR_SOURCE_STYLE.md) and run:

  ```sh
  python3 scripts/check_wir_source_style.py
  ```

## What does not belong here

- New high-level surface-language features. Those belong in
  [`weavec`](https://github.com/ahojukka5/weavec).
- Bootstrap surface-lowering changes. Those belong in
  [`weavec-bootstrap`](https://github.com/ahojukka5/weavec-bootstrap).
- Optimisation, packages, advanced types, or IDE behavior.
- Uncoordinated changes to the WIR or runtime ABI.
- A new runtime extern added only in Stage 1. Add it to `weavec0`, publish a new
  Stage 0 SDK, and then update `WEAVEC0_VERSION`.

## Development workflow

1. Create a focused branch.
2. Edit `src/*.wir` and add or update fixtures under `test/`.
3. Add new cases to `test/manifest.txt`.
4. Run `./build.sh` and confirm both compiler generations pass.
5. Regenerate and review goldens when emitter output changes:

   ```sh
   ./build.sh --regen-goldens
   git diff -- test/
   ```

6. Run the source-style checker and avoid new violations.
7. Update README, changelog, stabilization, or release documentation when a
   public contract changes.
8. Open a pull request.

CI validates:

- Linux x86-64 with the glibc Stage 0 SDK;
- Linux x86-64 with the musl Stage 0 SDK;
- macOS with the source fallback.

The release workflow additionally builds and smoke-tests both Stage 1 SDK
variants.

## SDK-affecting changes

For an output-SDK change:

1. update [`VERSION`](VERSION) intentionally;
2. validate both libc variants;
3. document compatibility and archive changes;
4. publish the Stage 1 SDK;
5. only then update the `WEAVEC1_VERSION` pin in `weavec-bootstrap`.

See [`docs/RELEASING.md`](docs/RELEASING.md).

## Licensing

By submitting a contribution, you agree that it is licensed under the Apache
License, Version 2.0. See [`LICENSE`](LICENSE).
