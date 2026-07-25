# LLVM IR fixture testing

This document describes the deterministic LLVM fixture system used by
`weavec1`.

## Fixture layout

Every positive case has:

```text
test/<name>.wir
test/<name>.expected.ll
```

Negative cases have only WIR input and an expected diagnostic recorded in
`test/manifest.txt`.

`build.sh` compiles each positive WIR file, compares the output with its LLVM
golden, assembles it with `llvm-as`, links it with `clang`, and checks the
program's declared exit code.

## Why fixtures are checked in

Fixtures provide:

- deterministic code-generation checks;
- immediate visibility into instruction, label, and ordering changes;
- reviewable regression evidence;
- executable documentation for WIR operators and interactions;
- a stable comparison surface between bootstrap generations.

A fixture mismatch is not fixed by blindly accepting new output. First identify
whether the change is a bug, an intentional semantic correction, or a justified
format change.

## Authoritative compiler generations

The first Stage 1 compiler is:

```text
build/weavec1
```

The build then constructs a second Stage 1 generation and compares its output
with the first:

```text
build/weavec1-selfhost
```

This artifact is the Stage 1 backend rebuilt by itself. It is unrelated to the
final [`weavec`](https://github.com/ahojukka5/weavec) compiler repository, which
was formerly named `weavec2`.

## Normal workflow

Build and verify all fixtures:

```bash
./build.sh
```

Regenerate goldens after an intentional emitter change:

```bash
./build.sh --regen-goldens
git diff -- test/
```

The regeneration mode updates missing or changed positive fixtures. Review the
entire diff before committing.

## Adding a test

1. Add `test/NN_name.wir`.
2. Add a `pass` or `fail` row to `test/manifest.txt`.
3. For a positive case, run:

   ```bash
   ./build.sh --regen-goldens
   ```

4. Inspect `test/NN_name.expected.ll`.
5. Run the normal build again without regeneration.
6. Commit the source, manifest entry, and golden together.

Do not add test enumeration directly to `build.sh`; the manifest is the
authoritative list.

## Reviewing an intentional fixture change

Check:

- function and extern signatures;
- LLVM types on every operand;
- block structure and terminators;
- label and temporary ordering;
- string lengths and escaping;
- declarations emitted only when required;
- runtime exit behavior;
- output identity between both Stage 1 generations.

A clear commit or PR description should explain why the LLVM output changed.

## Debugging a mismatch

Generate one actual output:

```bash
build/weavec1 test/NN_name.wir /tmp/actual.ll
diff -u test/NN_name.expected.ll /tmp/actual.ll
```

Compare the two Stage 1 generations directly:

```bash
build/weavec1 test/NN_name.wir /tmp/stage1.ll
build/weavec1-selfhost test/NN_name.wir /tmp/selfhost.ll
diff -u /tmp/stage1.ll /tmp/selfhost.ll
```

A divergence between these files is always a compiler or nondeterminism bug,
not a fixture update request.

Common causes include:

- uninitialized state;
- host-dependent behavior;
- unstable iteration order;
- inconsistent source paths;
- changes to label or temporary counters;
- incorrect cross-module declarations;
- accidental runtime ABI differences.

## Negative fixtures

A `fail` manifest row specifies the diagnostic substring expected from the
compiler. The test verifies that:

- the compiler exits nonzero;
- no nonempty LLVM output is produced;
- the diagnostic contains the expected text.

Negative cases do not have `.expected.ll` files.

## Fixture policy

Do:

- review fixture diffs carefully;
- keep each golden paired with its WIR source;
- regenerate rather than hand-edit generated LLVM;
- isolate code-generation changes from unrelated work;
- preserve deterministic output.

Do not:

- regenerate output without understanding the difference;
- accept bootstrap divergence;
- mix stale fixtures from different compiler versions;
- treat formatting drift as harmless without review;
- bypass `test/manifest.txt`.

## Relationship to the full compiler chain

```text
weavec0 → weavec1 → weavec-bootstrap → weavec
```

The fixtures in this repository stabilize the WIR-to-LLVM backend shared by the
bootstrap chain. Surface-language fixtures and final self-host behavior are
validated in `weavec-bootstrap` and `weavec`, respectively.

See [architecture](architecture.md) and [stabilization](stabilization.md).
