# weavec1 — Weave Stage 1 Compiler

[![ci](https://github.com/ahojukka5/weavec1/actions/workflows/ci.yml/badge.svg)](https://github.com/ahojukka5/weavec1/actions/workflows/ci.yml)

> The WIR-written compiler stage: built from the published `weavec0` SDK and
> published as the SDK consumed by `weavefront`.

## Overview

`weavec1` is the first Weave compiler written in WIR rather than hand-written
LLVM IR. It translates `.wir` source to `.ll` LLVM IR.

A complete build validates two consecutive generations of the same compiler:

```text
weavec0 v0.2.1 SDK
        ↓
compile src/*.wir
        ↓
 build/weavec1
        ↓
compile the same src/*.wir again
        ↓
 build/weavec2
        ↓
byte-identical LLVM output on the full ladder
```

In this repository, `build/weavec2` means the second bootstrap generation of
the WIR compiler. It is **not** the separate
[`ahojukka5/weavec2`](https://github.com/ahojukka5/weavec2) repository, which is
the compiler written in surface Weave.

## Current binary chain

`weavec1` sits between two published SDK boundaries:

```text
weavec0 v0.2.1 bootstrap SDK
        ↓
     weavec1 source build
        ↓
weavec1 v0.2.0 bootstrap SDK
        ↓
       weavefront
```

Linux x86-64 builds do not clone or rebuild `weavec0`. They download the
selected Stage 0 archive, verify it against `SHA256SUMS`, and reuse the cached
SDK on later builds.

`weavec1 v0.2.0` publishes a fully static compiler and the matching runtime
library so downstream stages do not rebuild Stage 0 or Stage 1.

## Prerequisites

### Debian or Ubuntu

```sh
sudo apt-get install -y clang curl llvm
```

Install `musl-tools` only for the musl build:

```sh
sudo apt-get install -y musl-tools
```

### macOS

```sh
brew install llvm git
export PATH="$(brew --prefix llvm)/bin:$PATH"
```

Linux x86-64 uses the published Stage 0 SDK by default. macOS currently uses a
pinned source fallback because no native macOS SDK is published.

## Quick start

```sh
git clone https://github.com/ahojukka5/weavec1.git
cd weavec1
./build.sh
```

The resulting bootstrap generations are:

```text
build/weavec1
build/weavec2
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

The default dependency is `weavec0 v0.2.1`.

```text
bin/weavec0
lib/weavec0-bootstrap.bc
lib/weavec0-bootstrap.o
lib/libweavec0-runtime.a
include/runtime.h
```

The build uses:

- `bin/weavec0` to compile Stage 1 WIR modules;
- `weavec0-bootstrap.o` as reusable compiler support code;
- `libweavec0-runtime.a` as the matching static runtime.

No `runtime.c` source file is required on the normal Linux path.

Environment overrides:

- `WEAVEC0_VERSION=v0.2.1` selects a published SDK release;
- `WEAVEC0_LIBC=glibc|musl` selects the Linux variant;
- `WEAVEC0_SDK=/path/to/sdk` uses an extracted SDK directly;
- `WEAVEC0_RELEASE_BASE=<url>` changes the release download base;
- `WEAVEC0=/path/to/source` explicitly selects a built source tree;
- `WEAVEC0_TAG=v0.2.1` selects the source-fallback tag.

## Build pipeline

The normal Linux build:

1. downloads or reuses a checksum-verified Stage 0 SDK;
2. compiles every WIR module under `src/` with `bin/weavec0`;
3. adds deterministic cross-module declarations;
4. compiles generated LLVM modules to native objects;
5. links `build/weavec1` with the Stage 0 bootstrap object and runtime;
6. runs all positive and negative compiler tests;
7. uses `build/weavec1` to build the second generation `build/weavec2`;
8. runs the same test ladder through the second generation;
9. compares every positive LLVM output byte for byte.

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

The SDK contains exactly what `weavefront` needs:

- a fully static WIR-to-LLVM compiler;
- the matching libc-specific runtime library;
- the runtime ABI header and package metadata.

The release workflow builds both variants, runs the complete bootstrap ladder,
rejects compiler executables with an ELF interpreter, and performs an SDK-only
compile-link-run smoke test.

See [`docs/RELEASING.md`](docs/RELEASING.md).

## Repository layout

```text
weavec1/
├── build.sh
├── VERSION
├── src/                         WIR compiler modules
├── test/
│   ├── manifest.txt
│   ├── NN_<name>.wir
│   └── NN_<name>.expected.ll
├── scripts/
│   ├── check_wir_source_style.py
│   └── package-linux-sdk.sh
├── docs/
│   ├── RELEASING.md
│   ├── STABILIZATION.md
│   ├── STABLE_CORE.md
│   └── WIR_SOURCE_STYLE.md
└── build/
    ├── vendor/weavec0-sdk/
    ├── downloads/
    ├── src-ll/ and link-ll/
    ├── src2-ll/ and link2-ll/
    ├── obj/ and obj2/
    ├── test-ll/ and test-bin/
    └── test2-ll/ and test2-bin/
```

## Test ladder

`test/manifest.txt` contains 60 cases: 55 positive and 5 expected failures.

Each positive case verifies that:

1. the compiler emits non-empty LLVM IR;
2. the output matches the checked-in golden;
3. `llvm-as` accepts it;
4. `clang` builds an executable;
5. the executable returns the declared exit code.

Negative cases must fail without producing LLVM IR and must emit the expected
diagnostic substring.

Useful examples:

- [`test/01_return_constant.wir`](test/01_return_constant.wir)
- [`test/07_if.wir`](test/07_if.wir)
- [`test/08_while.wir`](test/08_while.wir)
- [`test/16_extern_malloc_free.wir`](test/16_extern_malloc_free.wir)
- [`test/55_integration_nested_control_flow.wir`](test/55_integration_nested_control_flow.wir)

## Compiler chain

| Stage | Repository | Role |
|---|---|---|
| `weavec0` | [`ahojukka5/weavec0`](https://github.com/ahojukka5/weavec0) | Hand-written seed and published Stage 0 SDK. |
| `weavec1` | **this repository** | WIR-written compiler and published Stage 1 SDK. |
| `weavefront` | [`ahojukka5/weavefront`](https://github.com/ahojukka5/weavefront) | Surface Weave to WIR frontend. |
| `weavec2` | [`ahojukka5/weavec2`](https://github.com/ahojukka5/weavec2) | Self-hosted compiler written in surface Weave. |

Once the surface compiler is fully self-sustaining, this WIR stage and its
contract should remain stable.

## Source style

WIR modules follow [`docs/WIR_SOURCE_STYLE.md`](docs/WIR_SOURCE_STYLE.md).
The optional checker is run with:

```sh
python3 scripts/check_wir_source_style.py
```

## Known limitations

- WIR v1 is the stable boundary between Stage 0 and Stage 1.
- Published SDKs currently cover Linux x86-64 only.
- Source comments are not preserved in generated LLVM IR.
- The admitted extern set is intentionally small and versioned upstream.
- Diagnostics remain compact and mostly lack precise source ranges.
- The source-style checker reports pre-existing documentation gaps.

## License

Licensed under the Apache License, Version 2.0. See [`LICENSE`](LICENSE) and
[`NOTICE`](NOTICE).

## Contributing

Read [`CONTRIBUTING.md`](CONTRIBUTING.md),
[`docs/STABILIZATION.md`](docs/STABILIZATION.md), and
[`docs/RELEASING.md`](docs/RELEASING.md) before changing WIR, bootstrap
behavior, or the published SDK.
