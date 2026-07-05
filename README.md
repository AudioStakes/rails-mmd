# rails-mmd

`rails-mmd` is a planned standalone Ruby CLI/gem for generating Mermaid diagrams
from Rails and ActiveRecord applications.

The repository is currently in setup mode. It contains project operating
contracts, local development-tooling documentation, and a minimal Ruby gem/CLI
shell. It does not yet include Rails loading or diagram generation.

## Project Model

- Ruby-only project at the repository root.
- No Node, TypeScript, pnpm, npm, yarn, Nx, or monorepo workspace setup.
- No `packages/rails-mmd/` nesting.
- Serena is local development tooling only and is not a runtime dependency.

## Ruby And CLI

This repository pins MRI Ruby `4.0.5` in [`.ruby-version`](.ruby-version).
Ruby `4.0` is the selected stable branch for this project, and `4.0.5` was
selected as the available `4.0` patch at this issue-plan revision time. This is
not based on a claim that a downloads page alone labels `4.0.5` as the only
current stable release.

The current CLI shell supports only help and version smoke behavior:

```sh
asdf install ruby 4.0.5
ASDF_RUBY_VERSION=4.0.5 asdf exec bundle install
ASDF_RUBY_VERSION=4.0.5 asdf exec bundle exec exe/rails-mmd --help
ASDF_RUBY_VERSION=4.0.5 asdf exec bundle exec exe/rails-mmd --version
```

If your shell does not already resolve `ruby` and `bundle` through the pinned
toolchain, prefix commands with `ASDF_RUBY_VERSION=4.0.5 asdf exec`.

`rails-mmd generate` and all P0 feature options are intentionally absent until a
future implementation issue adds the command with matching contract coverage.

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
Repository drift guards and setup-mode release conditions are documented in
[`docs/development/setup-guards.md`](docs/development/setup-guards.md).

## P0 Contract

The P0 implementation contract is documented in
[`docs/p0-contract.md`](docs/p0-contract.md). Future implementation work should
read that file instead of relying on chat history or local design attachments.

## Serena Setup

Local setup for Codex and Serena MCP is documented in
[`docs/development/serena-mcp.md`](docs/development/serena-mcp.md).

The versioned Serena project configuration is `.serena/project.yml`. Local
overrides, logs, caches, language-server installs, and Codex user config remain
unversioned user-local state.
