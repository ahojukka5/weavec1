# WIR source style

This document defines the source style used by `weavec1` WIR files.

The project intentionally prioritizes explicitness, auditability, and
readability over compactness. The source should be easy for humans and LLMs to
navigate, review, and explain without relying on hidden conventions.

## Module headers

Every source module starts with a short architecture header:

- the file name
- the module responsibility
- a concise `Responsibilities:` list
- any important boundary or design note

Headers should explain where the module fits in the compiler, not repeat every
function name in the file.

## Section headers

Large modules are divided with section separators:

```lisp
; =============================================================================
; Expression parsing
; =============================================================================
```

Use section names that match searchable compiler concepts such as parser entry
points, operator lookup, block emission, AST storage, or token insertion.

## Function documentation

Every `(fn ...)` definition must have a preceding comment block. The first line
is the function name. The block explains why the function exists, its
parameters, and its return contract.

```lisp
; emit_stmt
;
; Dispatches one AST statement node to the matching LLVM statement emitter.
;
; Parameters:
;   ctx  - EmitContext pointer.
;   node - AST node index.
;
; Returns:
;   0 on success.
;   nonzero on emission failure.
(fn emit_stmt
  ...)
```

Prefer concrete contracts over generic summaries. For status-code functions,
state what zero and nonzero mean. For parser functions returning node indices,
state the failure sentinel.

## Invariants and notes

Document hidden AST layout assumptions near the functions that depend on them:

- required AST node kind
- field layout such as `a=condition`, `b=body`
- ownership and lifetime assumptions
- whether child nodes are emitted elsewhere

Use `Notes:` for intentional design tradeoffs. Linear dispatch chains, manual
storage layouts, explicit text emission, and repetitive low-level code are often
intentional in this bootstrap compiler.

## Spacing

Attach each documentation block directly to the following function. The
function opener keeps the function name on the same line:

```lisp
; ast_size
;
; Returns the size in bytes of the AST container header.
;
; Returns:
;   24.
(fn ast_size
  (params)
  ...)
```

Use one blank line between function blocks. Avoid random large whitespace
regions.

Files must not contain trailing whitespace and must end with a newline.

## Checker

Run the source style checker before committing documentation changes:

```sh
python3 scripts/check_wir_source_style.py
```

The checker is intentionally heuristic. It verifies the repository convention
that every function has a nearby documentation block, parameter documentation,
return documentation, consistent spacing, no trailing whitespace, and a final
newline.
