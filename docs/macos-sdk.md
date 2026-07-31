# macOS Stage 1 SDK

`weavec1` publishes native macOS SDKs so downstream bootstrap and final-compiler
development does not rebuild Stage 0 or Stage 1 implicitly.

## Package layout

A package is architecture-specific:

```text
weavec1-vX.Y.Z-macos-<arm64|x86_64>/
├── bin/weavec1
├── lib/libweave-runtime.a
├── include/runtime.h
├── SDK-MANIFEST
├── VERSION
├── README.md
├── LICENSE
└── NOTICE
```

The compiler is built from the pinned Stage 0 source during Stage 1 release
maintenance. The published package is then a stable binary dependency; downstream
repositories do not need the Stage 0 checkout.

## Self-containment contract

macOS cannot produce a fully static executable the way the Linux glibc and musl
SDKs do (Apple's libSystem must always be linked dynamically). The packaging
script enforces the closest practical equivalent instead: `bin/weavec1` must
depend on nothing but `/usr/lib/libSystem.B.dylib`, verified with `otool -L`.

## Build and package

```sh
brew install llvm gh
export PATH="$(brew --prefix llvm)/bin:$PATH"
./build.sh
scripts/package-macos-sdk.sh vX.Y.Z
```

The packaging script:

- copies the native `build/weavec1` compiler;
- verifies the compiler's only linked dependency is `libSystem.B.dylib`;
- compiles the matching Stage 0 runtime into `libweave-runtime.a`;
- includes the runtime header and versioned SDK manifest;
- compiles and runs a Stage 1 smoke program;
- writes an architecture-specific tar archive under `dist/`.

## Publish without GitHub Actions

The project does not depend on GitHub Actions being available. From a clean
checkout containing a locally qualified `build/weavec1`, run:

```sh
scripts/publish-macos-sdk.sh
```

The publisher derives `v<VERSION>`, builds the native archive, creates or updates
the matching GitHub Release, merges the archive checksum into `SHA256SUMS`, and
verifies that both assets are visible. It never rebuilds Linux packages.

Version `v0.3.2` adds native macOS packages only. The unchanged Linux Stage 1
SDK remains `v0.3.1`; downstream build scripts therefore select the dependency
version by host platform rather than assuming one release contains every host.

The release workflow may publish the same assets when Actions are available,
but it is optional and is not part of the manual development workflow.

## Compatibility

The SDK preserves the WIR core version 2 and runtime ABI contracts. Adding a
platform archive does not change compiler semantics. Downstream users select the
package matching their host architecture and must verify it against the release
checksums.
