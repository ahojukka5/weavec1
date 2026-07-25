# weavec1 architecture

`weavec1` is the WIR-written backend in the Weave bootstrap compiler chain. It
implements the complete stable WIR v2 to LLVM IR contract and publishes the
Stage 1 SDK consumed by `weavec-bootstrap`.

```text
weavec0 SDK
    ↓
compile weavec1 WIR modules
    ↓
first Stage 1 generation
    ↓
recompile the same modules
    ↓
second Stage 1 generation
    ↓
byte-identical LLVM output
```

The second generation is stored at `build/weavec1-selfhost`. It is the same
Stage 1 backend rebuilt by itself; it is not the final user-facing `weavec`
compiler.

## Compiler chain

```text
weavec0 → weavec1 → weavec-bootstrap → weavec
```

| Component | Role |
|---|---|
| [`weavec0`](https://github.com/ahojukka5/weavec0) | Hand-written LLVM-IR seed implementing the WIR v2 bootstrap profile required to build Stage 1. |
| `weavec1` | Complete stable WIR v2 backend and Stage 1 SDK. |
| [`weavec-bootstrap`](https://github.com/ahojukka5/weavec-bootstrap) | Deterministic surface-Weave-to-WIR-v2 bootstrap frontend. |
| [`weavec`](https://github.com/ahojukka5/weavec) | User-facing self-hosted compiler, formerly named `weavec2`. |

## WIR v2 boundary

WIR is the typed, deterministic tree representation between surface lowering and
LLVM emission:

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

Core version 2 is small, explicit, structured, human-readable, and close to LLVM
semantics. The complete admitted backend surface is defined by the Stage 1
implementation and the manifest-driven fixtures under `test/`.

Stage 0 deliberately implements only the profile needed to compile these source
modules. That profile is an implementation subset, not a separate WIR version.

## Source module graph

The authoritative production order is the `MODULES` array in `build.sh`. The
modules form these layers:

| Layer | Modules | Responsibility |
|---|---|---|
| Runtime and text | `runtime_bindings`, `strings`, `tokens` | Fixed host ABI, source slices, token storage, and shared text utilities. |
| AST | `ast_kinds`, `ast_storage`, `ast_accessors`, `ast_constructors` | Compact typed tree representation and construction. |
| Lexer | `lexer` | Deterministic bytes-to-token conversion. |
| Parser | `parser_state`, `parser_expect`, `parser_types`, `parser_expr`, `parser_stmt`, `parser_decl`, `parser_entry` | Versioned WIR shape, type, and declaration validation. |
| LLVM emitter | `emit_context`, `emit_text`, `emit_names`, `emit_types`, `emit_sections`, `emit_strings`, `emit_expr`, `emit_calls`, `emit_stmt`, `emit_control_flow`, `emit_declarations`, `emit_module` | Deterministic LLVM declarations, values, blocks, functions, and modules. |
| Driver | `driver_diag`, `driver`, `main` | File compilation, diagnostics, output publication, and CLI entry. |

Every production `src/*.wir` file must occur exactly once in `MODULES`. The
static repository audit rejects missing, duplicate, or unlisted modules.

## Build-time Stage 0 boundary

Linux x86-64 builds consume the published `weavec0` SDK:

```text
bin/weavec0
lib/libweavec0-runtime.a
```

`bin/weavec0` translates the Stage 1 WIR modules to LLVM IR. The resulting Stage
1 binaries contain the generated Stage 1 modules and the matching runtime
implementation; they do not embed the Stage 0 compiler.

macOS uses the pinned Stage 0 source fallback because no native macOS Stage 0 SDK
is currently published.

## Cross-module linking

Each generated Stage 1 module is assembled independently. The build derives
cross-module declarations from the generated definitions and source externs,
rejects conflicting signatures, then links the modules and runtime into the
first Stage 1 compiler.

This derived declaration graph avoids a second handwritten shell-level ABI
inventory.

## Bootstrap determinism

A complete build:

1. builds the first Stage 1 generation with `weavec0`;
2. runs the positive and negative WIR ladder;
3. rebuilds the same source modules with the first generation;
4. runs the same ladder through the second generation;
5. requires every positive LLVM output to be byte-identical.

Any generation divergence is a compiler or nondeterminism failure. See
[LLVM fixtures](llvm-fixtures.md).

## Runtime and SDK boundaries

Stage 1 publishes:

```text
bin/weavec1
lib/libweave-runtime.a
include/runtime.h
```

The compiler is a fully static build-time tool. The runtime library is the
matching libc-specific implementation required when linking programs from the
emitted LLVM IR. Downstream consumers must keep the compiler and runtime from the
same SDK variant together.

## Verification model

The repository enforces:

- exact production source and test inventories;
- exactly one `(core-version 2)` declaration per production module;
- resolved direct WIR calls;
- reachability of every source function from `main`;
- use of every source extern declaration;
- positive LLVM goldens and executable exit codes;
- negative diagnostic and no-output behavior;
- first-to-second-generation byte identity;
- glibc, musl, and macOS source-fallback builds;
- static SDK layout and installed-compiler smoke tests.

The machine-readable reachability report is written to
`build/audit/weavec1-reachability.json`.

## Change policy

Without a new WIR version, changes are limited to correctness fixes,
deterministic internal improvements, diagnostics, tests, documentation, and
compatible SDK packaging.

Changing or removing an admitted form, changing its type or semantics, breaking
valid WIR v2 programs, or changing the runtime ABI incompatibly requires a
coordinated contract and release transition.

See [stabilization](stabilization.md) and [releasing](releasing.md).
