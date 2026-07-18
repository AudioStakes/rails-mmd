# rails-mmd

`rails-mmd` is a standalone Ruby CLI/gem for generating Mermaid diagrams from
Rails and ActiveRecord applications.

The repository contains the P0 Ruby pipeline for loading a Rails app, producing
render plans, serializing Mermaid, and publishing local artifacts.

## Project Model

- Ruby-only project at the repository root.
- No Node, TypeScript, pnpm, npm, yarn, Nx, or monorepo workspace setup.
- No `packages/rails-mmd/` nesting.
- Serena is local development tooling only and is not a runtime dependency.

## Ruby And CLI

This repository develops on MRI Ruby `4.0.6` and supports maintained Ruby
versions `>= 3.3, < 4.1`. The local Rails matrix verifies three selected pairs:
Rails 7.2 on Ruby 4.0.6, and Rails 8.1 on Ruby 3.3.12 and 4.0.6.

The CLI supports help, version, and P0 generation:

```sh
asdf install ruby 4.0.6
ASDF_RUBY_VERSION=4.0.6 asdf exec bundle install
ASDF_RUBY_VERSION=4.0.6 asdf exec bundle exec exe/rails-mmd --help
ASDF_RUBY_VERSION=4.0.6 asdf exec bundle exec exe/rails-mmd --version
ASDF_RUBY_VERSION=4.0.6 asdf exec bundle exec exe/rails-mmd generate --help
```

If your shell does not already resolve `ruby` and `bundle` through the pinned
toolchain, prefix commands with `ASDF_RUBY_VERSION=4.0.6 asdf exec`.

`rails-mmd generate` exposes only P0 options: `--config`, `--output-dir`,
`--domain`, `--format`, and `--fail-on-warning`.

User-facing command behavior, artifact names, and exit codes are documented in
[`docs/usage.md`](docs/usage.md).

Dependency classifications are documented in
[`docs/development/dependencies.md`](docs/development/dependencies.md).
Ruby tooling commands are documented in
[`docs/development/tooling.md`](docs/development/tooling.md).
Local Git hooks are documented in
[`docs/development/hooks.md`](docs/development/hooks.md).
The no-hosted-CI local verification policy is documented in
[`docs/development/ci.md`](docs/development/ci.md).
P0 schema and Mermaid fixture scaffolding is documented in
[`docs/development/contract-fixtures.md`](docs/development/contract-fixtures.md).
The P0 blocking fixture matrix is documented in
[`docs/p0-blocking-fixture-matrix.md`](docs/p0-blocking-fixture-matrix.md).
Repository drift guards and setup-mode release conditions are documented in
[`docs/development/setup-guards.md`](docs/development/setup-guards.md).

## P0 Contract

The P0 implementation contract is documented in
[`docs/p0-contract.md`](docs/p0-contract.md). Future implementation work should
read that file instead of relying on chat history or local design attachments.
Rails Active Record support and implementation priorities are tracked in
[`docs/active-record-association-support.md`](docs/active-record-association-support.md).

## Artifact Schema Versions

P2 scoped-relationship metadata moved generated IR and render-plan artifacts
from schema version 1 to schema version 2. P2 STI support now moves both
artifacts from version 2 to version 3: IR entities can carry closed STI metadata,
while renderer entities carry a kind discriminator and class plans expose
explicit inheritance edges. Consumers must validate generated artifacts with
the schemas shipped by the same `rails-mmd` release. Configuration and
diagnostics artifacts remain at schema version 1.

There is no dual-version output mode. Strict v2 consumers must update for the
new required render-plan members and closed entity variants before consuming v3
IR or render plans. Association relationship objects retain their v2 shape.
Mermaid artifact filenames are unchanged.

P2 `delegated_type` support does not change the public schema version. Selecting
a delegator may add its declared, renderable concrete delegate tables to the
same domain as target-only nodes. Explicit exclusions and ownership by another
configured domain still win, and no unrelated associations are expanded.

## Serena Setup

Local setup for Codex and Serena MCP is documented in
[`docs/development/serena-mcp.md`](docs/development/serena-mcp.md).

The versioned Serena project configuration is `.serena/project.yml`. Local
overrides, logs, caches, language-server installs, and Codex user config remain
unversioned user-local state.
