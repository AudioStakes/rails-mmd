# Repository Instructions

This repository is a standalone Ruby CLI/gem project named `rails-mmd`.
The intended product is a Ruby command-line tool that generates Mermaid diagrams
from Rails/ActiveRecord applications. Runtime implementation is not present yet.

## Project Model

- Keep the gem at the repository root. Do not introduce a package subdirectory
  such as `packages/rails-mmd/`.
- Do not add Node or TypeScript workspace setup unless a later human-approved
  issue explicitly changes the project model.
- Do not create generated Node package-manager manifests or lockfiles.
- Do not apply monorepo policy assumptions from other AudioStakes repositories.
- Treat `docs/p0-contract.md` as the source of truth for P0 implementation
  scope. Do not rely on chat history, local attachments, or local-only paths for
  P0 behavior.

## Serena Workflow

- Before non-trivial code navigation or editing, activate this repository with
  Serena and read Serena's project instructions.
- Use the versioned `.serena/project.yml` as the repository-owned Serena project
  configuration.
- Treat `.serena/project.local.yml`, global Serena config, Codex MCP config,
  caches, logs, language-server installs, and other machine-local state as
  unversioned user-local files.
- `.serena/memories/**` is versionable/reviewable project memory by design, but
  this initial setup does not commit automatically generated or onboarding
  memories. Add future team-reviewed memories only through a later
  human-approved issue that defines review and revert ownership.

## Security

- Serena is trusted-local development tooling. It can execute shell commands and
  modify files, so use it only on a trusted local machine with a trusted client
  and trusted repository.
- Use additional sandboxing for security-sensitive work, or when the local
  machine, repository, client, package manager configuration, or task input is
  not fully trusted.
- Do not expose Serena network services beyond localhost unless a later
  human-approved issue explicitly approves that operating model.
- Keep Serena tool approvals narrow unless the current trusted task intentionally
  requires file-modifying or shell-executing tools.
