# weavec1 — Weave Stage 1 Bootstrap Compiler

[![ci](https://github.com/ahojukka5/weavec1/actions/workflows/ci.yml/badge.svg)](https://github.com/ahojukka5/weavec1/actions/workflows/ci.yml)

> The WIR-written compiler stage: built from the published `weavec0` SDK and
> published as the SDK consumed by `weavec-bootstrap`.

## Role

`weavec1` is the first Weave compiler written in WIR rather than hand-written
LLVM IR. It translates `.wir` source to `.ll` LLVM IR and forms the stable
backend used by the bootstrap frontend.

A complete build creates two consecutive generations of the same WIR compiler:

```text
weavec0 SDK
    ↓
compile src/*.wir
    ↓
build/weavec1
    ↓
compile the same sources again
    ↓
second Stage 1 generation
    ↓
byte-identical output on the full ladder
```

The second generation is named **`weavec1-selfhost`** and is written to
`build/weavec1-selfhost`. It is the same WIR compiler rebuilt by itself; it is
not the user-facing [`weavec`](https://github.com/ahojukka5/weavec) compiler.

## Compiler chain

```text
weavec0 v0.2.1 SDK
        ↓
      weavec1
        ↓
weavec1 v0.2.0 SDK
        ↓
weavec-bootstrap
        ↓
       weavec
```

| Component | Repository | Role |
|---|---|---|
| `weavec0` | [`ahojukka5/weavec0`](https://github.com/ahojukka5/weavec0) | Hand-written Stage 0 seed and SDK. |
| `weavec1` | **this repository** | WIR compiler and Stage 1 SDK. |
| `weavec-bootstrap` | [`ahojukka5/weavec-bootstrap`](https://github.com/ahojukka5/weavec-bootstrap) | Surface-to-WIR bootstrap frontend, formerly `weavefront`. |
| `weavec` | [`ahojukka5/weavec`](https://github.com/ahojukka5/weavec) | User-facing self-hosted compiler, formerly `weavec1-selfhost`. |

Normal users should use `weavec`. This repository is a reproducible bootstrap
stage and should change conservatively.

## Prerequisites

### Debian or Ubuntu

```sh
sudo apt-get install -y clang curl llvm
```

For the musl variant:

```sh
sudo apt-get install -y musl-tools
```

### macOS

```sh
brew install llvm git
export PATH="$(brew --prefix llvm)/bin:$PATH"
```

Linux x86-64 consumes the published Stage 0 SDK by default. macOS uses a pinned
source fallback because no native macOS Stage 0 SDK is published.

## Quick start

```sh
git clone https://github.com/ahojukka5/weavec1.git
cd weavec1
./build.sh
```

Build with the musl Stage 0 SDK:

```sh
WEAVEC0_LIBC=musl ./build.sh
```

Regenerate LLVM goldens only after an intentional emitter change:

```sh
./build.sh --regen-goldens
git diff -- test/
```

## Stage 0 dependency

The default dependency is `weavec0 v0.2.1`:

```text
bin/weavec0
lib/weavec0-bootstrap.bc
lib/weavec0-bootstrap.o
lib/libweavec0-runtime.a
include/runtime.h
```

The normal Linux build uses the compiler, reusable bootstrap object, and
matching static runtime directly. It does not require `runtime.c`.

Environment overrides:

- `WEAVEC0_VERSION=v0.2.1` selects the published SDK;
- `WEAVEC0_LIBC=glibc|musl` selects the Linux variant;
- `WEAVEC0_SDK=/path/to/sdk` uses an extracted SDK;
- `WEAVEC0_RELEASE_BASE=<url>` changes the release base;
- `WEAVEC0=/path/to/source` selects a built source tree;
- `WEAVEC0_TAG=v0.2.1` selects the source-fallback tag.

## Build pipeline

The normal Linux build:

1. downloads or reuses a checksum-verified Stage 0 SDK;
2. compiles every `src/*.wir` module with `bin/weavec0`;
3. generates deterministic cross-module declarations;
4. links `build/weavec1` with Stage 0 support and runtime;
5. runs positive and negative compiler tests;
6. builds the second Stage 1 generation from the same sources;
7. runs the same test ladder through it;
8. compares every positive LLVM output byte for byte.

A failed download, checksum mismatch, missing SDK component, test failure, or
bootstrap divergence aborts the build.

## Published Stage 1 SDK

Release `v0.2.0` introduced static Linux x86-64 SDKs for glibc and musl:

```text
weavec1-vX.Y.Z-linux-x86_64-<libc>/
├── bin/
│   └── weavec1
├── lib/
│   └── libweave-runtime.a
├── include/
│   └── runtime.h
├── SDK-MANIFEST
├── VERSION
├── README.md
├── LICENSE
└── NOTICE
```

The SDK contains exactly what `weavec-bootstrap` needs: a fully static
WIR-to-LLVM compiler, the matching runtime library, and ABI metadata.

See [`docs/RELEASING.md`](docs/RELEASING.md).

## Repository layout

```text
weavec1/
├── build.sh
├── VERSION
├── src/                         WIR compiler modules
├── test/                        WIR fixtures and LLVM goldens
├── scripts/                     source checks and SDK packaging
├── docs/                        WIR, stabilization, and release contracts
└── build/                       generated compilers and test outputs
```

## Test ladder

`test/manifest.txt` contains 60 cases: 55 positive and 5 expected failures.
Each positive case verifies compiler output, the LLVM golden, `llvm-as`, native
linking, and the declared exit code. Negative cases must fail without producing
LLVM IR and must include the expected diagnostic substring.

Useful examples:

- [`test/01_return_constant.wir`](test/01_return_constant.wir)
- [`test/07_if.wir`](test/07_if.wir)
- [`test/08_while.wir`](test/08_while.wir)
- [`test/16_extern_malloc_free.wir`](test/16_extern_malloc_free.wir)
- [`test/55_integration_nested_control_flow.wir`](test/55_integration_nested_control_flow.wir)

## Source style

WIR modules follow [`docs/WIR_SOURCE_STYLE.md`](docs/WIR_SOURCE_STYLE.md).
Run the optional checker with:

```sh
python3 scripts/check_wir_source_style.py
```

## Known limitations

- WIR v1 is the stable boundary between Stage 0 and Stage 1.
- Published SDKs currently cover Linux x86-64 only.
- Source comments are not preserved in generated LLVM IR.
- The admitted extern set is intentionally small and versioned upstream.
- Diagnostics remain compact and mostly lack precise source ranges.

## License

Licensed under the Apache License, Version 2.0. See [`LICENSE`](LICENSE) and
[`NOTICE`](NOTICE).

## Contributing

Read [`CONTRIBUTING.md`](CONTRIBUTING.md),
[`docs/STABILIZATION.md`](docs/STABILIZATION.md), and
[`docs/RELEASING.md`](docs/RELEASING.md) before changing WIR, bootstrap
behavior, or the published SDK.
