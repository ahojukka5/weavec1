# Stable WIR Core Architecture

This document defines the stable backend contract shared by the Weave bootstrap
compiler chain.

## WIR

WIR, the Weave Intermediate Representation, is the stable boundary between
surface lowering and LLVM emission:

```lisp
(core-module
  (core-version 1)
  (decls
    (fn main
      (params)
      (returns i32)
      (do
        (return (const_i32 42))))))
```

WIR is intentionally:

- small and explicit;
- close to LLVM semantics;
- deterministic;
- human-readable and auditable;
- versioned conservatively.

## Current compiler chain

```text
weavec0 → weavec1 → weavec-bootstrap → weavec
```

| Component | Role |
|---|---|
| [`weavec0`](https://github.com/ahojukka5/weavec0) | Hand-written LLVM-IR seed. Compiles WIR to LLVM IR and publishes the Stage 0 SDK. |
| `weavec1` | WIR-written backend. Compiles WIR to LLVM IR and publishes the Stage 1 SDK. |
| [`weavec-bootstrap`](https://github.com/ahojukka5/weavec-bootstrap) | Deterministic surface-Weave-to-WIR bootstrap frontend, formerly `weavefront`. |
| [`weavec`](https://github.com/ahojukka5/weavec) | Final user-facing self-hosted compiler, formerly `weavec2`. |

This repository also builds a second generation of `weavec1` to prove
self-hosting. The current physical path is `build/weavec2` for compatibility,
but the artifact is conceptually **`weavec1-selfhost`** and is unrelated to the
`weavec` repository.

## Bootstrap determinism

For every positive WIR fixture, the first and second Stage 1 generations must
emit byte-identical LLVM IR.

`build.sh` validates this by:

1. building `build/weavec1` with `weavec0`;
2. building the second Stage 1 generation with `build/weavec1`;
3. running the complete positive and negative ladder through both;
4. comparing every positive LLVM output byte for byte.

A divergence is always a build failure. It may indicate nondeterministic code,
uninitialised state, host-dependent behavior, or a compiler self-hosting bug.

## Stable backend contract

WIR version 1 includes explicit:

- scalar types: `i8`, `i32`, `i64`, `bool`, and `void`;
- pointer operations and memory loads/stores;
- arithmetic and comparisons;
- locals, parameters, function calls, and extern declarations;
- `do`, `if`, `while`, and `return` control flow;
- string pointer constants;
- module and declaration structure.

The authoritative admitted shapes are the implementation and the fixtures under
[`test/`](../test/).

### Allowed changes

- bug fixes that restore intended semantics;
- deterministic implementation improvements;
- diagnostics and documentation improvements;
- explicitly versioned additions coordinated with `weavec0`;
- release and packaging improvements that preserve the SDK contract.

### Changes requiring a new contract version

- removing or changing an existing operator;
- changing an operator's type or semantics;
- breaking previously valid WIR version 1 programs;
- changing the runtime ABI incompatibly;
- introducing nondeterministic output.

Future incompatible language additions must use a new `(core-version N)` and a
documented migration path.

## Surface language relationship

WIR is not the user language:

```text
surface Weave
      ↓
weavec-bootstrap or weavec frontend
      ↓
WIR version 1
      ↓
weavec1 or weavec backend
      ↓
LLVM IR
```

New user-facing language work belongs primarily in `weavec`. The bootstrap
frontend only needs enough surface support to reproduce that compiler from the
lower stages.

## LLVM fixtures

Each positive case has:

```text
test/<name>.wir
test/<name>.expected.ll
```

The build verifies that the compiler output matches the checked-in fixture,
assembles with `llvm-as`, links with `clang`, and returns the declared exit code.
Negative cases must fail without producing LLVM IR and must include the expected
diagnostic substring.

See [`LLVM_FIXTURES.md`](LLVM_FIXTURES.md).

## Runtime and SDK boundaries

Linux x86-64 builds consume the published `weavec0` SDK:

```text
bin/weavec0
lib/weavec0-bootstrap.o
lib/libweavec0-runtime.a
include/runtime.h
```

This repository publishes the Stage 1 SDK consumed by `weavec-bootstrap`:

```text
bin/weavec1
lib/libweave-runtime.a
include/runtime.h
```

Both SDK boundaries are versioned. Downstream pins change only after the
corresponding upstream release exists and its checksums and contents have been
verified.

## Project principles

- **Auditability:** transformations and generated LLVM remain inspectable.
- **Determinism:** the same WIR produces the same LLVM text.
- **Explicit lowering:** no hidden conversions, allocations, or operators.
- **Reproducibility:** each stage can be rebuilt from the previous published
  stage.
- **LLM-friendly structure:** stable naming, simple formats, and small explicit
  operations.

## Verification

Run:

```bash
./build.sh
```

A passing build confirms:

- the Stage 0 SDK can build `weavec1`;
- the complete WIR ladder passes;
- the second Stage 1 generation can rebuild the same compiler;
- both generations emit identical output;
- the source and SDK contracts remain compatible.
