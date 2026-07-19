# P0 Blocking Fixture Matrix

This matrix lists the P0 failures that must block generation or publication.
It is a fixture planning document for executable specs and sample Rails apps:
new blocking behavior should add or update a row here before implementation is
claimed complete.

## Fixture Rules

- Every blocking fixture must use a project-root-relative output directory.
- Pre-output fatal fixtures must assert no artifacts are written.
- Post-output blocking fixtures usually assert diagnostics are published and
  affected `.mmd` and render-plan artifacts are omitted. Publish-phase write
  failures are the exception: they may fall back to sanitized stderr and may
  leave previous managed artifacts intact.
- Warning-only fixtures must stay out of this matrix unless they are paired with
  `--fail-on-warning`; warning omission behavior belongs in relationship and
  diagnostics fixtures.
- Fixtures must not require Mermaid CLI, hosted CI, Node, TypeScript, or network
  services.

## Matrix

| code | phase | trigger fixture | exit | attachment | publication effect |
|---|---|---|---:|---|---|
| `CONFIG_NOT_FOUND` | config | no `rails_mmd.yml` and no readable `--config` path | 2 | stderr diagnostics | pre-output fatal; no files |
| `CONFIG_SCHEMA_INVALID` | config | invalid config shape, unsupported output format, or invalid domain ID | 2 | stderr diagnostics | pre-output fatal; no files |
| `CONFIG_DOMAIN_NOT_FOUND` | config | `--domain` names no configured domain | 2 | stderr diagnostics | pre-output fatal; no files |
| `OUTPUT_DIRECTORY_INVALID` | output setup | output directory is absolute, escapes root, empty, backslash, NUL, drive, UNC, or unsafe symlink | 2 | stderr diagnostics | pre-output fatal; no files |
| `DOMAIN_MODEL_NOT_FOUND` | domain resolution | included or excluded model constant cannot be resolved, including explicitly named anonymous or non-resolvable descendants | 2 | diagnostics JSON | blocks selected artifacts |
| `DOMAIN_MODEL_NOT_RENDERABLE` | domain resolution | selected model is abstract, STI subclass, or lacks table name | 2 | diagnostics JSON | blocks selected artifacts |
| `DOMAIN_EMPTY` | domain resolution | include/exclude rules leave no renderable selected models | 2 | diagnostics JSON | blocks selected artifacts |
| `RAILS_LOAD_FAILED` | Rails boot | application environment raises before eager load | 2 | diagnostics JSON or stderr before output | blocks selected artifacts |
| `RAILS_EAGER_LOAD_FAILED` | Rails boot | eager loading raises after Rails boot | 2 | diagnostics JSON or stderr before output | blocks selected artifacts |
| `MULTI_DB_UNSUPPORTED` | schema probe | selected models require multiple connection contexts | 2 | diagnostics JSON | blocks selected artifacts |
| `MODEL_TABLE_MISSING` | schema probe | selected model table is missing or inaccessible | 2 | diagnostics JSON | blocks selected artifacts |
| `MODEL_PRIMARY_KEY_UNSUPPORTED` | schema probe | primary key metadata is missing, empty, nested, has duplicate members, or is otherwise invalid | 2 | diagnostics JSON | blocks selected artifacts |
| `SAFE_TOKEN_COLLISION` | tokenization | suffix exhaustion leaves an unresolved safe-token collision | 0 or 3 | diagnostics JSON | warning when suffix resolves; fatal when suffix exhaustion remains |
| `MERMAID_SERIALIZATION_FAILED` | serialization | render plan cannot be serialized to valid Mermaid text | 3 | diagnostics JSON | no `.mmd` or render plan published |
| `OUTPUT_WRITE_FAILED` | publish | atomic write, rename, cleanup, or rollback fails | 4 | diagnostics JSON or stderr | publish failed |
| `INTERNAL_ERROR` | internal | unexpected exception escapes a P0 stage | 99 | diagnostics JSON or stderr | abort invocation |

## Exit Policy Coverage

The blocking fixture set must prove these exit policy groups:

- exit `2`: config, output setup, Rails boot, domain resolution, and schema
  probe errors.
- exit `3`: Mermaid serialization failure and unresolved safe-token collision.
- exit `4`: output write or atomic publish failure.
- exit `99`: internal implementation failure.

Warning diagnostics default to exit `0`. A separate `--fail-on-warning` fixture
must prove warning diagnostics promote the invocation to exit `1` without
changing artifact publication rules.

## User-Facing Assertions

Each user-facing fixture should assert:

- stdout is empty for `generate`.
- stderr contains sanitized diagnostics only for pre-output fatal failures and
  publish failures that cannot rely on diagnostics files.
- diagnostics JSON never contains raw absolute paths, credentials, backtraces,
  process IDs, temp paths, random seeds, or unsafe tokens.
- successful and warning-only publish paths keep stderr empty.
