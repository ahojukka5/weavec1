# Changelog

All notable changes to `weavec1` are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning follows
[SemVer](https://semver.org/). The project remains pre-1.0, but WIR and the
published SDK are maintained as explicit bootstrap contracts.

## [Unreleased]

## [0.2.0] — 2026-07-24

### Added

- Static Linux x86-64 Stage 1 SDKs for glibc and musl.
- A fully static `bin/weavec1` compiler and matching
  `lib/libweave-runtime.a` in each archive.
- Runtime headers, SDK manifest, version metadata, and SHA-256 checksums.
- SDK-only compile-link-run smoke tests for both libc variants.
- VERSION-driven GitHub Release publication and release documentation.

### Changed

- Linux builds consume the published `weavec0 v0.2.1` bootstrap SDK rather
  than clone and rebuild Stage 0.
- Downloaded Stage 0 archives are verified against `SHA256SUMS` and cached
  under `build/vendor/weavec0-sdk/`.
- `weavec1` and its second bootstrap generation link against the Stage 0
  bootstrap object and matching static runtime library; `runtime.c` is no
  longer required on the normal Linux path.
- CI now validates Linux glibc SDK, Linux musl SDK, and macOS source-fallback
  builds.
- `weavefront` consumes the published Stage 1 SDK on Linux.

### Documentation

- Clarified that `build/weavec2` in this repository is the second generation of
  the WIR compiler, not the separate surface-compiler repository.
- Added the Stage 0 input SDK and Stage 1 output SDK contracts to the README.

## [0.1.0] — 2026-05-26

The first public release of `weavec1`.

### Added

- Apache-2.0 licensing and SPDX headers.
- `CONTRIBUTING.md`, this changelog, and repository formatting files.
- GitHub Actions CI on Linux and macOS.
- `--regen-goldens` support.
- `test/manifest.txt` with 60 cases: 55 positive and 5 negative.

### Changed

- Renamed `tests/` to `test/`.
- Removed the sibling-directory assumption. The initial release fetched and
  built the pinned `weavec0 v0.2.0` source tree when `WEAVEC0` was unset.
- Expanded the README into standalone build, test, architecture, and
  contribution documentation.

### Fixed

- The source-style checker reports missing documentation markers as normal
  violations rather than raising `ValueError`.
