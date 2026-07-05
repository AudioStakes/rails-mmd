# rails-mmd

`rails-mmd` is a planned standalone Ruby CLI/gem for generating Mermaid diagrams
from Rails and ActiveRecord applications.

The repository is currently in setup mode. It contains project operating
contracts and local development-tooling documentation, but it does not yet
include Ruby gem files, a CLI executable, Rails loading, diagram generation,
hooks, or CI.

## Project Model

- Ruby-only project at the repository root.
- No Node, TypeScript, pnpm, npm, yarn, Nx, or monorepo workspace setup.
- No `packages/rails-mmd/` nesting.
- Serena is local development tooling only and is not a runtime dependency.

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
