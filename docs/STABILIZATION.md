# WIR Core Stabilization

This document records the stabilized WIR core version 2 and Stage 0/Stage 1
bootstrap boundary.

## Current chain

```text
weavec0 → weavec1 → weavec-bootstrap → weavec
```

`weavec0` is the minimal hand-written seed. `weavec1` is the WIR-written backend
and complete stable-core implementation. The upper stages lower surface Weave to
WIR and provide the user-facing compiler.

## Stabilized guarantees

- `build.sh` builds two consecutive Stage 1 generations.
- Both generations run the same positive and negative ladder.
- Every positive LLVM fixture is compared byte for byte.
- LLVM assembly, native linking, runtime exit codes, SDK contents, and checksums
  are validated.
- Linux builds consume `weavec0 v0.4.0`; `weavec1 v0.3.0` publishes the matching
  Stage 1 SDK.

## Version 2 boundary

WIR v2 stabilizes `(core-module (core-version 2) ...)`, the admitted types and
operators, deterministic WIR-to-LLVM emission, and the runtime ABI. Current
compilers reject core version 1; immutable older releases retain that contract.

Stage 0 deliberately implements only the bootstrap profile exercised by the
pinned `weavec1` source modules. Stage 1 implements the complete stable v2
backend. Expanding Stage 0 merely to match Stage 1 is not a goal.

Without a new WIR version, changes are limited to bug fixes, deterministic
internal improvements, clearer diagnostics, tests, and compatible SDK packaging.
Changing semantics, removing admitted Stage 1 forms, breaking valid v2 programs,
or changing the runtime ABI incompatibly requires coordinated versioning.

## Dependency release order

1. release `weavec0`;
2. update, validate, and release `weavec1`;
3. update `weavec-bootstrap`;
4. update and self-host `weavec`.

Downstream pins never move before upstream assets and `SHA256SUMS` exist.

## Verification

`./build.sh` verifies Stage 0 acquisition, first-generation construction, the
complete ladder, second-generation construction, and byte-identical output.
