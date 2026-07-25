# Documentation

`weavec1` is the complete stable WIR v2 backend in the bootstrap compiler chain.
Its documentation defines the backend architecture, stabilization policy,
fixture contract, source conventions, and published Stage 1 SDK.

## Documents

- [Architecture](architecture.md) — WIR v2 backend contract, module graph,
  runtime boundary, and self-rebuild model.
- [Stabilization](stabilization.md) — guarantees and permitted changes on the
  frozen WIR v2 line.
- [LLVM fixtures](llvm-fixtures.md) — deterministic golden and negative-fixture
  policy.
- [Source style](source-style.md) — WIR module and function documentation rules.
- [Releasing](releasing.md) — Stage 1 SDK packaging and publication.
- [Contributing](../CONTRIBUTING.md) — change policy and required checks.
- [Changelog](../CHANGELOG.md) — released and pending changes.

## Naming policy

Files under `docs/` use lowercase kebab-case names. Conventional repository-root
files such as `README.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `LICENSE`, and
`NOTICE` retain their standard names.
