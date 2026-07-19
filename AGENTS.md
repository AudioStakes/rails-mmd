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

## Verification Workflow

- Use the local `pre-commit` and `pre-push` hooks as final evidence before
  claiming a setup or implementation PR is ready.
- Use direct Rake tasks for diagnosis, narrowing failures, or reproducing hook
  output before rerunning the hook.
- Preserve the repair-first loop: run/autocorrect first, inspect the diff, stage
  explicit repairs, then let read-only checks run.

## Git hook test isolation

- Nested Git-repo specs must wrap temporary repository helpers so `GIT_DIR`,
  `GIT_WORK_TREE`, `GIT_INDEX_FILE`, `GIT_OBJECT_DIRECTORY`, and
  `GIT_ALTERNATE_OBJECT_DIRECTORIES` are saved, cleared, and restored around the
  temporary repository lifecycle.
- Add deterministic assertions that inner temporary repository commits do not alter
  the outer repository HEAD or tracked files.
- If a push transport exports repository-discovery variables into a revision
  that lacks this regression test, run the `pre-push` hook directly and set
  `LEFTHOOK=0` only for the transport whose checks have just passed.

## P1 Engineering Records

- Before P1 work, read [`docs/p1/README.md`](docs/p1/README.md) and the applicable
  feature records. Keep phase rules and feature details there, not in this file.
- For runtime-compatibility scope changes, prefer editing
  `fixtures/rails_matrix/matrix.yml` as an explicit `pairs:` list and keep
  documentation aligned in `docs/p1/01-runtime-compatibility/*` to avoid
  accidental Cartesian matrix drift.
- For association features, verify Rails reflection behavior in the shared real
  app and extend its exact relationship oracle on every declared matrix pair;
  keep isolated unit doubles for failure paths that real model declarations
  cannot express.
- Resolve polymorphic associations from a two-pass reflection inventory. Never
  call `klass` on a polymorphic `belongs_to`; derive concrete targets only from
  selected matching inverse `as:` reflections.
- Probe hidden association tables through `SchemaProbe` and pass only normalized
  metadata to `RelationshipBuilder`; never add raw database connection access
  to relationship construction.
- Rails does not store a `delegated_type` type list in reflection options.
  Discover `<role>_types` only when its generated method source file exactly
  matches the active runtime's `ActiveRecord::DelegatedType` source file, then
  pass a normalized family whitelist and entity selection origin downstream.
  Auto-expanded delegates are target-only; do not traverse their unrelated
  associations, nested delegated families, join tables, or STI descendants.
- Matrix fixture-family selectors are harness-only environment. Remove
  `RAILS_MMD_MATRIX_FIXTURE_FAMILY` and `RAILS_MMD_MATRIX_PAIR` from child Rails
  processes so runtime behavior and redaction cannot depend on test selectors.
