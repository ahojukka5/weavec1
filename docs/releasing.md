# Releasing weavec1

`weavec1` publishes static Linux x86-64 SDKs for both glibc and musl, and native
macOS SDKs for arm64 and x86_64. The SDK is the supported binary input for
downstream bootstrap compiler stages.

## SDK contents

Each Linux archive contains:

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

`bin/weavec1` is fully static. `libweave-runtime.a` is the matching libc-specific
runtime required when linking LLVM IR emitted by the compiler.

Each macOS archive (`weavec1-vX.Y.Z-macos-<arm64|x86_64>/`) has the same layout
without a libc suffix. See [macOS Stage 1 SDK](macos-sdk.md) for the
self-containment contract macOS uses in place of full static linking.

## Release policy

The version is stored in `VERSION`. GitHub Actions may build and publish all
configured platform packages when credits and runners are available, but release
correctness must not depend on Actions.

A packaging-only release may add a new host without rebuilding unchanged host
artifacts. In particular, `v0.3.2` adds native macOS packages while Linux builds
continue to consume the unchanged `v0.3.1` SDK. Downstream resolvers must select
the version matching the host package instead of assuming every release has every
platform.

## Local validation and packaging

Install LLVM, binutils, musl tools, curl, Python 3, and the usual C toolchain.
Before packaging, run:

```bash
python3 scripts/check_docs.py
python3 scripts/check_wir_source_style.py
python3 scripts/audit_wir_reachability.py
```

Then build one Linux libc variant from a clean directory and package the selected
version:

```bash
version="v$(tr -d '[:space:]' < VERSION)"

rm -rf build
WEAVEC0_LIBC=glibc ./build.sh
scripts/package-linux-sdk.sh glibc "$version" dist

rm -rf build
WEAVEC0_LIBC=musl ./build.sh
scripts/package-linux-sdk.sh musl "$version" dist
```

The Linux packaging script verifies static linkage and compiles, links, and runs
a small program using only the files placed in the SDK directory.

On macOS, package the native host architecture:

```bash
./build.sh
scripts/package-macos-sdk.sh "$version" dist
```

## Manual macOS publication

When GitHub Actions are unavailable, publish the current Mac architecture from a
clean, locally qualified checkout:

```bash
scripts/publish-macos-sdk.sh
```

The script derives `v<VERSION>`, invokes the package script, creates or updates
the corresponding GitHub Release with `gh`, preserves checksums for existing
assets, replaces the current architecture archive atomically, and verifies the
published asset names. Run it separately on each architecture that is being
published.

## Release assets

A full cross-platform release may contain:

```text
weavec1-vX.Y.Z-linux-x86_64-glibc.tar.gz
weavec1-vX.Y.Z-linux-x86_64-musl.tar.gz
weavec1-vX.Y.Z-macos-arm64.tar.gz
weavec1-vX.Y.Z-macos-x86_64.tar.gz
SHA256SUMS
```

A platform-addition release may contain only the newly introduced host archives
and `SHA256SUMS`. Downstream builds must pin a version that actually contains the
selected package and verify the archive against that release's checksums before
extraction.

## Release checklist

Before publishing:

- verify the documentation, source-style, and reachability audits;
- verify both compiler generations pass the same positive and negative ladder;
- verify byte-identical positive LLVM output;
- inspect every package layout and manifest being published;
- verify `SHA256SUMS`;
- confirm the selected `weavec0` release already exists;
- update `weavec-bootstrap` only after the required Stage 1 host asset exists.

See [architecture](architecture.md) and [stabilization](stabilization.md).
