# Changelog

All notable changes to `weavec1` are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning is
[SemVer](https://semver.org/) with the caveat that `0.x` is the
bootstrap phase: minor versions may break things until `weavec1`
reaches its goal of bootstrapping `weavec2` reliably, at which point
the contract freezes.

## [Unreleased]

## [0.1.0] — 2026-05-26

The first public release of `weavec1`.

### Added
- Apache-2.0 licensing (`LICENSE`, `NOTICE`, SPDX headers on every
  owned source file).
- `CONTRIBUTING.md` describing the very narrow merge bar.
- `CHANGELOG.md` (this file).
- `.editorconfig` and `.gitattributes` for consistent line endings /
  indentation.
- GitHub Actions CI matrix (`ubuntu-latest`, `macos-latest`) that
  fetches the pinned `weavec0` dependency and runs the full ladder.
- `--regen-goldens` flag on `build.sh` for accepting golden updates
  with reviewable `git diff`.
- `test/manifest.txt` enumerates every test case (60 cases:
  55 positive + 5 negative), replacing the inline enumeration in
  `build.sh`.

### Changed
- Layout rename: `tests/` → `test/`, matching `weavec0`/`weavec2`.
- `build.sh` no longer assumes a sibling `../src-bootstrap-llvm/`
  directory. Instead it honours the `WEAVEC0` env var (path to a
  pre-built weavec0 source tree); when unset, it git-clones the
  pinned `WEAVEC0_TAG` (default `v0.2.0`) from
  `https://github.com/ahojukka5/weavec0` into `build/vendor/weavec0`
  and builds it there. Vendored copy is gitignored.
- Reworked README from a 26-line stub to a full standalone-project
  README (overview, prerequisites, quick start, layout, build, test
  ladder, examples, where weavec1 fits, source style, known
  limitations, license, contributing).

### Fixed
- `scripts/check_wir_source_style.py` no longer crashes with
  `ValueError` when a function block is missing its `; Parameters:`
  marker; it now records the missing marker as a normal style
  violation. (The checker still reports 17 pre-existing violations
  in the current source tree; cleaning these up is a separate
  follow-up.)
