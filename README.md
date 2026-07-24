# weavec1 — Weave Stage 1 Compiler

[![ci](https://github.com/ahojukka5/weavec1/actions/workflows/ci.yml/badge.svg)](https://github.com/ahojukka5/weavec1/actions/workflows/ci.yml)

> The second-stage Weave compiler. Written in WIR, compiled by the published
> [`weavec0`](https://github.com/ahojukka5/weavec0) bootstrap SDK, and emitting
> LLVM IR.

## Overview

`weavec1` is the first compiler in the Weave chain written in the Weave
intermediate representation (WIR), rather than hand-written LLVM IR. It
translates `.wir` files to `.ll` files and then compiles itself again as
`weavec2`.

A complete build verifies bootstrap determinism:

```text
published weavec0 SDK
        ↓
compile weavec1 sources
        ↓
      weavec1
        ↓
compile the same sources again
        ↓
      weavec2
        ↓
byte-identical LLVM output on the test surface
```

Once `weavec2` is stable, the WIR contract and this compiler stage should mostly
freeze. See [`docs/STABILIZATION.md`](docs/STABILIZATION.md) and
[`docs/STABLE_CORE.md`](docs/STABLE_CORE.md).

## Bootstrap dependency

Linux x86-64 builds consume the versioned `weavec0` bootstrap SDK. They do not
clone or rebuild `weavec0` from source.

The default dependency is:

```text
weavec0 v0.2.1
Linux x86-64 glibc SDK
```

The SDK contains:

```text
bin/weavec0
lib/weavec0-bootstrap.bc
lib/weavec0-bootstrap.o
lib/libweavec0-runtime.a
include/runtime.h
```

`build.sh` downloads the selected archive and `SHA256SUMS`, verifies the
archive, extracts it under `build/vendor/weavec0-sdk/`, and reuses the cached
copy on later builds.

The compiler executable translates WIR to LLVM IR. The bootstrap object and
static runtime library are linked directly into `weavec1` and `weavec2`; no
`runtime.c` source file is required.

macOS currently uses the source fallback because no native macOS bootstrap SDK
is published yet.

## Prerequisites

Python is not required for a normal compiler build.

### Debian or Ubuntu

```sh
sudo apt-get install -y clang curl llvm musl-tools
```

`musl-tools` is only required when building with `WEAVEC0_LIBC=musl`.

### macOS

```sh
brew install llvm git
export PATH="$(brew --prefix llvm)/bin:$PATH"
```

The macOS source fallback requires `git` to fetch the pinned `weavec0` source
tag.

## Quick start

```sh
git clone https://github.com/ahojukka5/weavec1.git
cd weavec1
./build.sh
```

The first Linux build downloads the pinned SDK. Subsequent builds reuse the
verified cached copy.

To build the musl variant:

```sh
WEAVEC0_LIBC=musl ./build.sh
```

The resulting compilers are:

```text
build/weavec1
build/weavec2
```

## Build configuration

```sh
./build.sh
./build.sh --regen-goldens
```

Environment overrides:

- `WEAVEC0_VERSION=v0.2.1` selects the published SDK release.
- `WEAVEC0_LIBC=glibc|musl` selects the Linux SDK and static linker.
- `WEAVEC0_SDK=/path/to/sdk` uses an already extracted SDK directory.
- `WEAVEC0_RELEASE_BASE=<url>` overrides the GitHub release download base.
- `WEAVEC0=/path/to/source` explicitly uses a built `weavec0` source tree.
- `WEAVEC0_TAG=v0.2.1` selects the source fallback tag.

The normal Linux pipeline is:

1. Download or reuse the checksum-verified `weavec0` SDK.
2. Compile every WIR module under `src/` with `bin/weavec0`.
3. Add deterministic cross-module declarations.
4. Compile the generated LLVM modules to native objects.
5. Link the objects with `weavec0-bootstrap.o` and
   `libweavec0-runtime.a`.
6. Run the complete `weavec1` test ladder.
7. Use `weavec1` to build `weavec2` from the same WIR source.
8. Run the same ladder through `weavec2`.
9. Compare the LLVM output of every positive test for byte identity.

A failed download, checksum mismatch, missing SDK component, failed test, or
bootstrap divergence aborts the build.

## Repository layout

```text
weavec1/
├── build.sh
├── src/                         WIR compiler modules
├── test/
│   ├── manifest.txt
│   ├── NN_<name>.wir
│   └── NN_<name>.expected.ll
├── docs/
├── scripts/
│   └── check_wir_source_style.py
└── build/
    ├── vendor/weavec0-sdk/      extracted SDK cache
    ├── downloads/               verified release downloads
    ├── src-ll/ and link-ll/     weavec1 LLVM modules
    ├── src2-ll/ and link2-ll/   weavec2 LLVM modules
    ├── obj/ and obj2/           native link objects
    ├── test-ll/ and test-bin/
    └── test2-ll/ and test2-bin/
```

## Test ladder

`test/manifest.txt` contains positive and negative compiler cases. Every
positive case verifies:

1. the compiler emits non-empty LLVM IR;
2. `llvm-as` accepts the output;
3. `clang` builds the generated program;
4. the executable returns the declared exit code;
5. the LLVM IR matches the checked-in golden file.

Negative cases require the compiler to fail without producing LLVM IR and to
emit the expected diagnostic substring.

Golden output is updated only intentionally:

```sh
./build.sh --regen-goldens
git diff -- test/
```

## Examples

Every `.wir` file under [`test/`](test) is an executable example. Useful entry
points include:

- [`test/01_return_constant.wir`](test/01_return_constant.wir)
- [`test/07_if.wir`](test/07_if.wir)
- [`test/08_while.wir`](test/08_while.wir)
- [`test/16_extern_malloc_free.wir`](test/16_extern_malloc_free.wir)
- [`test/55_integration_nested_control_flow.wir`](test/55_integration_nested_control_flow.wir)

## Compiler chain

| Stage | Repository | Role |
|---|---|---|
| `weavec0` | [`ahojukka5/weavec0`](https://github.com/ahojukka5/weavec0) | Hand-written LLVM-IR seed and published bootstrap SDK. |
| `weavec1` | **this repository** | WIR-written compiler built by the Stage 0 SDK. |
| `weavefront` | [`ahojukka5/weavefront`](https://github.com/ahojukka5/weavefront) | Surface Weave to WIR frontend. |
| `weavec2` | [`ahojukka5/weavec2`](https://github.com/ahojukka5/weavec2) | Self-hosted surface-Weave compiler. |

## Source style

WIR modules follow [`docs/WIR_SOURCE_STYLE.md`](docs/WIR_SOURCE_STYLE.md).
The optional heuristic checker is run with:

```sh
python3 scripts/check_wir_source_style.py
```

## Known limitations

- WIR v1 is the frozen contract between `weavec0` and `weavec1`.
- Published bootstrap SDKs currently cover Linux x86-64 only.
- Source comments are not preserved in generated LLVM IR.
- The admitted extern set remains intentionally small.
- Diagnostics remain compact and mostly lack precise source ranges.
- The source-style checker still reports pre-existing documentation gaps.

## License

Licensed under the Apache License, Version 2.0. See [`LICENSE`](LICENSE) and
[`NOTICE`](NOTICE).

## Contributing

Read [`CONTRIBUTING.md`](CONTRIBUTING.md), the known limitations above, and
[`docs/STABILIZATION.md`](docs/STABILIZATION.md) before changing the WIR
contract or bootstrap behavior.
