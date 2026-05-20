# weavec1

`weavec1` is the WIR-written bootstrap compiler. It is built by `weavec0` and
then runs the same WIR test ladder as the seed compiler.

The test inputs are intentionally copied from `weavec0` so the first
WIR-written compiler is tested against the same behavioral surface as the
hand-written seed compiler.

The build ladder checks:

1. WIR input compiles to LLVM IR
2. generated LLVM IR matches golden fixtures
3. generated LLVM IR is accepted by `llvm-as`
4. generated LLVM IR compiles with `clang`
5. executable behavior matches expected exit code
6. selected invalid WIR inputs fail cleanly

When self-hosting is enabled by `build.sh`, the same ladder is also run with
the `weavec2` binary produced by `weavec1`.
