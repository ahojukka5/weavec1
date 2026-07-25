# Stable WIR Core Architecture

This document defines the backend contract shared by the Weave bootstrap
compiler chain.

## WIR core version 2

WIR is the typed, deterministic boundary between surface lowering and LLVM
emission:

```lisp
(core-module
  (core-version 2)
  (decls
    (fn main
      (params)
      (returns i32)
      (do
        (return (const_i32 42))))))
```

Core version 2 is small, explicit, close to LLVM semantics, human-readable, and
versioned conservatively. Core version 1 remains reproducible through immutable
older compiler releases; current compilers reject it.

## Compiler chain

```text
weavec0 → weavec1 → weavec-bootstrap → weavec
```

| Component | Role |
|---|---|
| [`weavec0`](https://github.com/ahojukka5/weavec0) | Hand-written LLVM-IR seed. Implements only the WIR v2 bootstrap profile required to compile `weavec1`. |
| `weavec1` | WIR-written backend. Implements the complete stable WIR v2 backend and publishes the Stage 1 SDK. |
| [`weavec-bootstrap`](https://github.com/ahojukka5/weavec-bootstrap) | Deterministic surface-Weave-to-WIR bootstrap frontend. |
| [`weavec`](https://github.com/ahojukka5/weavec) | User-facing self-hosted compiler. |

The Stage 0 bootstrap profile is intentionally a strict implementation subset:
it accepts exactly the forms used by the pinned Stage 1 source modules. This is
not a second language version. Stage 1 owns the complete backend surface used by
downstream compilers.

## Bootstrap determinism

`build.sh` builds `weavec1` with `weavec0`, rebuilds the same compiler with the
first generation, runs the complete positive and negative ladder through both,
and requires byte-identical LLVM output. Any divergence is a build failure.

## Stable backend contract

WIR core version 2 includes explicit scalar and pointer types, arithmetic and
comparisons, memory operations, locals and parameters, typed calls and externs,
structured control flow, string pointer constants, and module declarations.
The authoritative admitted shapes are the Stage 1 implementation and fixtures
under `test/`.

Allowed changes without a new core version are correctness fixes, deterministic
implementation improvements, diagnostics, tests, and packaging changes that
preserve semantics. Removing or changing an admitted form, changing its type or
semantics, breaking valid v2 programs, or changing the runtime ABI incompatibly
requires a new core version and coordinated release.

## Runtime and SDK boundaries

Stage 1 consumes the minimal Stage 0 SDK:

```text
bin/weavec0
lib/libweavec0-runtime.a
include/runtime.h
```

Stage 1 publishes:

```text
bin/weavec1
lib/libweave-runtime.a
include/runtime.h
```

Downstream pins move only after the corresponding upstream release and checksums
exist.

## Verification

Run `./build.sh`. A passing build confirms the Stage 0 SDK can build Stage 1,
the full WIR v2 ladder passes, the second generation rebuilds the compiler, and
both generations emit identical output.
