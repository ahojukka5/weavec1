# Changelog

All notable changes to `weavec1` are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning follows
[SemVer](https://semver.org/). The project remains pre-1.0, but WIR and the
published SDK are maintained as explicit bootstrap contracts.

## [Unreleased]

### Added

- A required source and test inventory audit covering production modules,
  WIR core versions, manifest cases, and LLVM goldens.
- A machine-readable WIR call-graph report that requires every source function
  to be reachable from `main` and every source extern declaration to be used.
- Active division, remainder, bitwise, and shift coverage from the previously
  dormant `59_new_operators` fixture.

### Changed

- CI and release builds run the frozen-source audits before constructing the
  compiler and preserve audit and build diagnostics on failure.
- Parser and driver diagnostic helpers now meet the documented source contract.
- The compiler driver has one real file-compilation entry point rather than a
  forwarding compatibility layer.

### Removed

- The unbuilt `stage0_bridge.wir` compatibility residue.
- Unreachable token helpers, AST and emitter accessors, runtime wrappers, and
  the unused string-compilation entry point.
- Unused `strcmp` and `weave_rt_fatal` source declarations.

## [0.3.0] — 2026-07-25

### Added

- A regression proving the superseded core version 1 contract is rejected.
- Documentation of the distinction between the minimal Stage 0 bootstrap
  profile and the complete Stage 1 WIR v2 backend.

### Changed

- Migrated all Stage 1 source modules and fixtures to WIR core version 2.
- The compiler now requires core version 2 and emits `; core-version: 2`.
- The default Stage 0 dependency is `weavec0 v0.4.0`.
- Bumped the Stage 1 SDK version to 0.3.0.
- Renamed the second Stage 1 bootstrap generation from the ambiguous
  `build/weavec2` path to `build/weavec1-selfhost`.
- Renamed the corresponding build variables, directories, diagnostics, and
  documentation to distinguish it from the user-facing `weavec` compiler.
- Stage 1 now uses the Stage 0 compiler strictly as a build-time WIR translator;
  final Stage 1 binaries no longer link `weavec0-bootstrap.o` or the equivalent
  Stage 0 source-fallback bitcode modules.
- The required Stage 0 SDK subset is reduced to `bin/weavec0` and the matching
  static runtime library.

### Documentation

- Updated downstream terminology after `weavefront` was renamed to
  `weavec-bootstrap` and the surface compiler repository `weavec2` was renamed
  to `weavec`.
- Defined the second Stage 1 generation as `weavec1-selfhost`.
- Clarified the compile-time boundary between the Stage 0 compiler and the
  generated Stage 1 implementation.

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
- CI validates Linux glibc SDK, Linux musl SDK, and macOS source-fallback
  builds.
- The repository then named `weavefront` began consuming the published Stage 1
  SDK on Linux. It is now named `weavec-bootstrap`.

### Documentation

- Clarified that the historical path `build/weavec2` in this repository is the
  second generation of the WIR compiler, not the surface-compiler repository.
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
