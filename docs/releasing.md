# Releasing weavec1

`weavec1` publishes static Linux x86-64 SDKs for both glibc and musl. The SDK is
the supported binary input for downstream bootstrap compiler stages.

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

`bin/weavec1` is fully static. `libweave-runtime.a` is the matching libc-specific
runtime required when linking LLVM IR emitted by the compiler.

## Automatic release

The version is stored in `VERSION`. A push to `master` builds both SDKs and
creates `v<VERSION>` when that release does not already exist. Existing VERSION
releases are left unchanged.

An explicit `v*` tag rebuilds and replaces the assets for that tag. This is
reserved for correcting a broken release workflow or damaged assets.

## Local validation and packaging

Install LLVM, binutils, musl tools, curl, Python 3, and the usual C toolchain.
Before packaging, run:

```bash
python3 scripts/check_docs.py
python3 scripts/check_wir_source_style.py
python3 scripts/audit_wir_reachability.py
```

Then build one libc variant from a clean directory and package the version
selected by `VERSION`:

```bash
version="v$(tr -d '[:space:]' < VERSION)"

rm -rf build
WEAVEC0_LIBC=glibc ./build.sh
scripts/package-linux-sdk.sh glibc "$version" dist

rm -rf build
WEAVEC0_LIBC=musl ./build.sh
scripts/package-linux-sdk.sh musl "$version" dist
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

## Release checklist

Before publishing:

- verify the documentation, source-style, and reachability audits;
- verify both compiler generations pass the same positive and negative ladder;
- verify byte-identical positive LLVM output;
- inspect both static SDK layouts and manifests;
- verify `SHA256SUMS`;
- confirm the selected `weavec0` release already exists;
- update `weavec-bootstrap` only after the new Stage 1 assets exist.

See [architecture](architecture.md) and [stabilization](stabilization.md).
