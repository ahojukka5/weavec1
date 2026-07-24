# WIR Core Stabilization

This document records the stabilization of WIR version 1 and the Stage 0/Stage 1
bootstrap boundary.

## Milestone

The stabilization milestone was reached in May 2026 and has since been extended
with versioned Linux bootstrap SDKs.

The current chain is:

```text
weavec0 → weavec1 → weavec-bootstrap → weavec
```

- `weavec0` is the hand-written seed and Stage 0 SDK.
- `weavec1` is the WIR-written backend and Stage 1 SDK.
- `weavec-bootstrap` is the surface-to-WIR bootstrap frontend, formerly
  `weavefront`.
- `weavec` is the final user-facing compiler, formerly `weavec1-selfhost`.

## Stabilized guarantees

### Bootstrap determinism

`build.sh` builds two consecutive generations of the Stage 1 WIR compiler and
requires byte-identical LLVM output for every positive fixture.

The second generation currently uses the historical path `build/weavec1-selfhost`, but
it is conceptually `weavec1-selfhost`; it is not the final `weavec` product.

A divergence fails the build immediately.

### Integration coverage

The ladder includes single-feature, interaction, edge, and compile-fail cases.
The manifest is the authoritative test enumeration:

```text
test/manifest.txt
```

Each positive case verifies emitted LLVM, the checked-in golden, LLVM assembly,
native linking, and the declared exit code. Negative cases verify failure
behavior and diagnostics.

### LLVM fixture contract

Every positive fixture has:

```text
test/<name>.wir
test/<name>.expected.ll
```

Generated output is compared byte for byte on every build. Fixture changes must
be intentional, reviewed, and explained.

See [`LLVM_FIXTURES.md`](LLVM_FIXTURES.md).

### Published SDK boundaries

Linux x86-64 builds consume `weavec0 v0.2.1` SDKs for glibc or musl rather than
rebuilding Stage 0.

`weavec1 v0.2.0` publishes the static compiler and matching runtime consumed by
`weavec-bootstrap`.

SDK archives are versioned, checksum-verified, and tested independently of the
source checkout.

## What is stable

WIR version 1 stabilizes:

- the `(core-module (core-version 1) ...)` module shape;
- admitted scalar and pointer types;
- arithmetic, comparison, memory, call, and control-flow operators;
- operator semantics and type expectations;
- deterministic WIR-to-LLVM emission;
- the runtime ABI used by the compiler chain;
- the Stage 0 and Stage 1 SDK component contracts.

The implementation and fixtures under `test/` are the executable authority.

## What may change

Without a new WIR version:

- bug fixes restoring intended behavior;
- deterministic internal implementation improvements;
- clearer diagnostics;
- documentation and testing improvements;
- compatible SDK packaging improvements.

With explicit versioning and coordinated releases:

- new operators or types;
- runtime ABI additions;
- changes that require updates in both `weavec0` and `weavec1`.

The following are not acceptable in WIR version 1:

- changing existing operator semantics;
- removing admitted forms;
- breaking valid version 1 programs;
- nondeterministic code generation;
- silently changing the runtime ABI.

## Where new language work belongs

Normal surface-language development belongs in
[`weavec`](https://github.com/ahojukka5/weavec).

`weavec-bootstrap` should gain only the surface support required to reproduce
the final compiler from the lower stages. `weavec1` should remain focused on
the stable WIR backend and SDK.

## Dependency release order

A contract-affecting change moves upward in this order:

1. change and release `weavec0` when Stage 0 or runtime support changes;
2. update, validate, and release `weavec1`;
3. update and validate `weavec-bootstrap`;
4. update and validate `weavec` including self-host checks.

Downstream version pins must not move before the upstream release and
`SHA256SUMS` are available.

## Verification

Run:

```bash
./build.sh
```

The build verifies:

1. Stage 0 SDK acquisition and checksums;
2. first-generation `weavec1` construction;
3. the complete positive and negative ladder;
4. second-generation Stage 1 construction;
5. the same ladder through the second generation;
6. byte-identical bootstrap output.

A passing build confirms the stabilized WIR core remains reproducible and
deterministic.
