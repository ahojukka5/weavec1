# Releasing weavec1

`weavec1` publishes static Linux x86-64 SDKs for both glibc and musl.
The SDK is the supported binary input for downstream compiler stages.

## SDK contents

Each archive contains:

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

`bin/weavec1` is fully static. `libweave-runtime.a` is the matching
libc-specific runtime required when linking LLVM IR emitted by the compiler.

## Automatic release

The version is stored in `VERSION`. A push to `master` builds both SDKs and
creates `v<VERSION>` when that release does not already exist. Existing
VERSION releases are left unchanged.

An explicit `v*` tag rebuilds and replaces the assets for that tag. This is
reserved for correcting a broken release workflow or damaged assets.

## Local packaging

Install LLVM, binutils, musl tools, curl, and the usual C toolchain. Then run:

```bash
WEAVEC0_LIBC=glibc ./build.sh
scripts/package-linux-sdk.sh glibc v0.3.0 dist

WEAVEC0_LIBC=musl ./build.sh
scripts/package-linux-sdk.sh musl v0.3.0 dist
```

The packaging script verifies static linkage and compiles, links, and runs a
small program using only the files placed in the SDK directory.

## Release assets

A normal release contains:

```text
weavec1-vX.Y.Z-linux-x86_64-glibc.tar.gz
weavec1-vX.Y.Z-linux-x86_64-musl.tar.gz
SHA256SUMS
```

Downstream builds must pin the release version and verify the archive against
`SHA256SUMS` before extraction.
