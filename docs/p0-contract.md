# rails-mmd P0 Contract

This document is the repository source of truth for the first implementation
scope of `rails-mmd`. It is self-contained and does not require chat
attachments or local design files.

## Purpose

P0 reads a required `rails_mmd.yml`, boots and eager-loads a Rails application,
selects configured ActiveRecord base models by exact domain configuration, and
renders deterministic Mermaid `erDiagram` and `classDiagram` artifacts.

P0 renders only selected-domain ActiveRecord base models and scalar,
non-polymorphic, unscoped, direct-foreign-key `belongs_to` relationships.

## Supported Scope

P0 supports:

- Rails boot and eager load.
- Model inventory without schema reads.
- Exact include/exclude domains.
- Selected-entity-only schema probing.
- Renderable base models only.
- Selected connection guard.
- Strict `belongs_to` relationship eligibility.
- `attributes: none` and `attributes: keys`.
- Primary-key and foreign-key attributes only.
- Closed diagnostics catalog.
- Redaction before external output.
- Deterministic IDs and safe tokens.
- Canonical digests.
- Atomic artifact publishing.

## Excluded Scope

P0 excludes:

- `.erdconfig`.
- No-config default domain.
- Depth expansion.
- Glob or regex domain matching.
- Runtime Mermaid CLI validation.
- Cache.
- Compatibility mode.
- STI subclass rendering.
- Polymorphic or concrete interface rendering.
- `delegated_type` specialization.
- Warning generation for non-`belongs_to` associations.
- HABTM or through relationship rendering.
- Unique-key attributes.
- `attributes: all`.
- Content attributes.

## CLI Contract

P0 exposes only:

```text
rails-mmd generate --config PATH --output-dir DIR --domain ID --format er|class|both --fail-on-warning
```

Unsupported CLI options must not appear in help: `strict`, `no-strict`,
`allow-partial`, `validate`, `cache`, `compatibility`, `depth`, glob or regex
matching, and attributes outside `none` and `keys`.

### CLI And Config Defaults

- `--config` defaults to `rails_mmd.yml`.
- The config file is required.
- Missing config is fatal `CONFIG_NOT_FOUND`.
- P0 never auto-creates a default domain.
- Output directory precedence is `--output-dir` > `output.directory` >
  `docs/rails_mmd`.
- CLI and config output directories must be project-root-relative safe paths.
- `--domain ID` selects one configured domain.
- Omitting `--domain` renders all configured domains.
- Unknown domain is fatal `CONFIG_DOMAIN_NOT_FOUND`.
- Format precedence is `--format` > `output.format` > `both`.
- Allowed formats are `er`, `class`, and `both`.
- `--fail-on-warning` is an optional boolean flag.
- `--fail-on-warning` defaults to `false`.
- If present, any warning diagnostic makes the invocation exit `1` after
  diagnostics and artifacts follow the normal error/warning policy.

### Non-CLI Config Defaults

- `output.attributes` defaults to `keys`.
- Allowed `output.attributes` values are `none` and `keys`.
- `output.direction` defaults to `LR`.
- Allowed directions are `TB`, `BT`, `LR`, and `RL`.
- `domains.<id>.exclude_models` defaults to `[]`.

### Precedence

- Explicit CLI overrides config for config-backed fields.
- Config overrides documented defaults.
- `--domain` has no config equivalent; omitted means all configured domains.
- `--fail-on-warning` has no config equivalent in P0 and defaults false.

## Config Rules

- Load YAML with safe loading only.
- Do not evaluate ERB.
- Do not perform arbitrary class loading from config parsing.
- Do not permit YAML aliases.
- `version: 1` is required.
- `domains` is required and must be non-empty.
- Model names are exact Ruby constants.
- Domain IDs use the grammar in this document.
- Output directories must be project-root-relative safe paths.

### Config Shape

Minimal valid config:

```yaml
version: 1
domains:
  core:
    include_models:
      - User
    exclude_models: []
output:
  directory: docs/rails_mmd
  format: both
  attributes: keys
  direction: LR
```

Top-level keys:

- `version`: required integer, exactly `1`.
- `domains`: required object, non-empty.
- `output`: optional object, defaults field-by-field.
- Unknown top-level keys are `CONFIG_SCHEMA_INVALID`.
- Configured domain IDs must match the domain ID grammar below. Invalid domain
  IDs are `CONFIG_SCHEMA_INVALID`.

Domain keys:

- `domains.<id>.include_models`: required array of one or more exact Ruby
  constant strings.
- `domains.<id>.exclude_models`: optional array of exact Ruby constant strings,
  defaults to `[]`.
- Empty `include_models`, omitted `include_models`, non-array domain lists, and
  non-string model entries are `CONFIG_SCHEMA_INVALID`.
- Unknown fields are `CONFIG_SCHEMA_INVALID`.

Output keys:

- `output.directory`: optional string, defaults to `docs/rails_mmd`.
- `output.format`: optional string, allowed values `er`, `class`, and `both`,
  defaults to `both`.
- `output.attributes`: optional string, allowed values `none` and `keys`,
  defaults to `keys`.
- `output.direction`: optional string, allowed values `TB`, `BT`, `LR`, and
  `RL`, defaults to `LR`.
- Unknown output fields are `CONFIG_SCHEMA_INVALID`.

### Output Directory Safety

Normalize `--output-dir` or `output.directory` lexically before filesystem
writes. Accept only non-empty relative paths that remain inside the project root
after expanding `.` and `..` segments.

Reject with `OUTPUT_DIRECTORY_INVALID`:

- Empty strings.
- Absolute paths.
- Paths that normalize to `.`.
- Paths that escape the project root via `..`.
- Paths containing NUL.
- Paths containing backslash (`\`). P0 treats backslash as unsafe rather than as
  an alternate separator.
- Drive or UNC forms.
- Symlink escapes after resolving existing path components.

Symlinked directories are allowed only when their resolved real path remains
inside the project root. Unsafe path evidence must be redacted before stderr,
diagnostics, logs, or artifacts.

Domain ID grammar is lowercase ASCII snake_case:

```ruby
\A[a-z][a-z0-9]*(?:_[a-z0-9]+)*\z
```

This means one lowercase ASCII letter, followed by lowercase ASCII letters or
digits, with single underscores only between non-empty alphanumeric segments.

Accepted examples:

- `core`
- `billing_v2`
- `admin`
- `api2`

Rejected examples:

| value | reason |
|---|---|
| `Core` | uppercase |
| `billing-v2` | hyphen |
| `_internal` | leading underscore |
| `2core` | leading digit |
| `billing_` | trailing underscore |
| `billing__core` | double underscore |
| `core/api` | slash |
| `core.api` | dot |
| `顧客` | non-ASCII |
| empty string | empty |
| `core\n` | newline |
| `core\r\n` | carriage return/newline |
| `core\napi` | embedded newline |
| `core\t` | tab |
| ` core` | leading space |
| `core ` | trailing space |

## Model Inventory

Inventory records exactly:

- `ruby_constant`
- `abstract_class`
- `base_class`
- `table_name`
- `connection_context_id`
- `renderable`
- `renderability_reason`

Inventory must not read table existence, columns, indexes, or foreign keys.

Inventory includes only named ActiveRecord descendants whose Ruby constant can be
resolved back to the same class object. Anonymous descendants and descendants
whose `name` is nil, blank, or not constant-resolvable are ignored by inventory,
are never domain-selectable, and do not produce diagnostics unless explicitly
named in config, in which case they are unresolved constants.

Renderable means:

- ActiveRecord model.
- Concrete class.
- `abstract_class? == false`.
- `model.base_class == model`.
- Table name is obtainable.

Included STI subclasses or abstract models produce
`DOMAIN_MODEL_NOT_RENDERABLE` during domain resolution when they appear in
`include_models` or `exclude_models`. Model inventory may observe STI subclasses
or abstract models outside the resolved domain set, but domain resolution ignores
them because no configured domain selected them.

## Stage Handoffs

| Stage | Inputs | Outputs | Consumer |
|---|---|---|---|
| Config loader | CLI argv, `rails_mmd.yml` | validated config object, selected CLI overrides | Rails boot, domain resolution, publisher |
| Rails boot/eager load | validated config, project root | loaded Rails environment or load diagnostics | model inventory |
| Model inventory | ActiveRecord descendants | inventory records only | domain resolution |
| Domain resolution | config domains, inventory records | selected renderable entity set or diagnostics | selected schema probe |
| Selected schema probe | selected renderable entities | selected schema metadata and connection context set | relationship builder, cardinality evidence |
| Relationship builder | selected entities, schema metadata, reflections | relationship records and omission diagnostics | IR builder |
| IR builder | selected entities, attributes, relationships, diagnostics | normalized internal IR payload | render-plan generator |
| Render-plan generator | normalized IR payload, output config | ER/class render-plan payloads with `digest_sha256` | Mermaid serializer, publisher |
| Mermaid serializer | render plans | `.mmd` text payloads or serialization diagnostics | publisher |
| Redactor | diagnostics, exceptions, paths, comments, logs | sanitized external-output payloads | publisher, stderr |
| Publisher | render plans, `.mmd` payloads, diagnostics | atomic artifact set or write diagnostics | filesystem |

IR is an internal payload owned by the IR builder. It is not a publishable P0
artifact. Render plans are the first publishable structured rendering payloads.

IR key attributes carry their source DB/Rails type as a string so the
render-plan builder can project a serializer-facing type without reading schema
metadata or Rails objects.

P1-03 emits an FK key attribute on the entity that actually holds the FK. For
direct `has_many` / `has_one`, this is the associated target entity and is not
necessarily the relationship declaration owner.

## Domain Resolution

Resolution order is exact:

1. Resolve selected domain IDs.
2. Resolve exact `include_models`.
3. Resolve exact `exclude_models`.
4. Emit `DOMAIN_MODEL_NOT_FOUND` for unresolved include or exclude constants.
5. Emit `DOMAIN_MODEL_NOT_RENDERABLE` for non-renderable include or exclude
   constants.
6. Compute final set as includes minus excludes.
7. Emit `DOMAIN_EMPTY` when the final set is empty.

P0 has no depth expansion and no virtual auto-include.

## Selected Schema Probe

Only selected domain entities are probed for:

- Table metadata.
- Column metadata.
- Primary-key metadata.
- Foreign-key metadata.
- Unique metadata.

Domain-outside model schema is never read.

Table or inaccessible metadata failure is `MODEL_TABLE_MISSING`.
Missing or non-scalar primary key is `MODEL_PRIMARY_KEY_UNSUPPORTED`.

Selected renderable entities must use exactly one connection context. Two or
more selected connection contexts produce `MULTI_DB_UNSUPPORTED`.
Domain-outside connection contexts are ignored.

`connection_context_id` is the canonical JSON serialization of the selected
model connection's Rails `connection_db_config.name`, role, shard, adapter name,
database identifier, host, port, and username after redaction of secret values.
Role and shard always participate. Two Rails configs that point at the same
physical database but have different config names, roles, shards, adapters,
database identifiers, hosts, ports, or usernames are distinct contexts. Secret
connection material such as passwords, URLs with credentials, tokens, and raw DSN
strings never participate in emitted IDs.

## Relationship Eligibility

A relationship is eligible only when all conditions hold:

- Owner entity is selected.
- Reflection is scalar `belongs_to`.
- Reflection is non-polymorphic.
- Reflection is unscoped.
- Target constant resolves.
- Target is renderable.
- Target is in the same domain.
- Owner foreign key has exactly one column.
- Owner foreign-key column exists.
- Target primary key has exactly one column.
- Association primary key equals target primary key.
- Target primary-key column exists.

P1-03 extends Rails 7.2/8.1 eligibility to direct, unscoped,
non-polymorphic-owner `has_many` and `has_one`. Their scalar target FK must exist,
their `active_record_primary_key` must equal the declaring owner's actual
primary key, and both entities must be selected in the same domain. `as:`
variants remain omitted. Same-physical-tuple declarations are grouped by
the P1-04 rule below without an additional warning.

P1-04 canonicalizes every supported direct physical tuple regardless of
explicit, automatic, absent, or disabled inverse metadata. Canonical orientation
is FK holder to referenced entity. The public ID is
`relationships/<holder_table>/<fk_column>/<referenced_table>/<primary_key>`;
label priority is `belongs_to`, `has_one`, `has_many`, then lexical declaration
ID. Thus inverse declarations and enumeration order do not change the edge.

P1-05 supports unscoped, non-polymorphic `has_many :through` and
`has_one :through` when Rails infers the source and every model in the full
reflection chain resolves, is renderable, and is selected in the same domain.
The normalized path is `collect_join_chain` in owner-forward order, with its
outer declaration hop replaced by the resolved terminal source-reflection name.
Direct physical edges remain, and one semantic edge is added per normalized path with
ID `relationships/<owner_table>/through/<path...>/<target_table>`. Its owner
cardinality is `0..many`; target cardinality is `0..many` for `has_many` and
`0..1` for `has_one`. Explicit `source:`, `source_type:`, scopes, and
polymorphic hops remain omitted for later priorities.

Omitted relationship diagnostics:

| condition | diagnostic |
|---|---|
| Polymorphic `belongs_to` | `ASSOCIATION_POLYMORPHIC_OMITTED` |
| Scoped `belongs_to` | `ASSOCIATION_SCOPED_OMITTED` |
| Unresolved target | `ASSOCIATION_TARGET_UNRESOLVED` |
| Unresolved through reflection/intermediate | `ASSOCIATION_THROUGH_UNRESOLVED` |
| Unresolved through source/nested chain | `ASSOCIATION_SOURCE_UNRESOLVED` |
| Target non-renderable | `ASSOCIATION_TARGET_NOT_RENDERABLE_OMITTED` |
| Target outside domain | `DOMAIN_RELATIONSHIP_OMITTED` |
| Composite key | `ASSOCIATION_COMPOSITE_KEY_OMITTED` |
| Missing owner or target key column | `ASSOCIATION_KEY_COLUMN_MISSING` |
| Custom or non-primary target key | `ASSOCIATION_NON_PRIMARY_KEY_OMITTED` |
| Unsafe association name | `ASSOCIATION_NAME_UNSUPPORTED_OMITTED` |
| Non-`belongs_to` macro (P1-02) | `ASSOCIATION_MACRO_OMITTED` |

The P0 baseline emitted no warnings for non-`belongs_to` associations. P1-02
extends Rails 7.2/8.1 output with one warning per omitted macro. P1-03 renders
eligible direct `has_many` / `has_one`; unsupported variants retain an existing
specific omission code or `ASSOCIATION_MACRO_OMITTED`.

For P0, scoped `belongs_to` means the association reflection itself has a scope
lambda or proc (`reflection.scope.present?`). A target model `default_scope` does
not by itself make an otherwise unscoped `belongs_to` scoped for this rule.

Relationship labels are derived from the association name exactly as declared.
Accepted association names match
`\A[a-z][a-z0-9]*(?:_[a-z0-9]+)*[!?=]?\z`; the optional trailing `?`, `!`, or `=`
is removed before rendering. Labels use the sanitized association name without
that suffix, are non-empty, and are emitted as Mermaid text labels after comment
sanitization. Examples: `account` and `billing_account` are accepted; `Account`,
`billing-account`, `billing account`, `_account`, `account_`, `account__owner`,
`account/name`, and `account\nname` are unsafe and produce
`ASSOCIATION_NAME_UNSUPPORTED_OMITTED`.

## Redaction

Redact before external output:

- Diagnostic messages.
- Diagnostic free-form metadata.
- Exception summaries.
- stderr.
- Debug logs.
- External command output.
- Mermaid comments.
- Displayed output paths.

Path handling:

- Paths inside the project root may be displayed project-root-relative.
- Absolute project-root prefixes are not emitted raw.
- Paths outside the project root are not emitted raw.
- Symlink escapes are not emitted raw.
- Drive and UNC forms are not emitted raw.
- NUL-containing paths are not emitted raw.
- Path traversal evidence is not emitted raw.

Secret handling:

- Environment variable values are never emitted to stderr or artifacts.
- Credential-looking free-text keys and metadata keys are never emitted to stderr
  or artifacts.
- URL credentials are never emitted to stderr or artifacts.
- Passwords, tokens, API keys, database URLs, and raw connection strings are
  never emitted to stderr or artifacts.

Exception handling:

- P0 never emits raw backtraces.
- Exception output uses `exception_class`, sanitized summary, and
  `backtrace: null`.

Structured identifiers are allowed as structured data after canonical encoding
and syntax sanitization. They do not pass through free-text redaction:

- Entity IDs.
- Attribute IDs.
- Relationship IDs.
- Diagnostic IDs.
- Subject IDs.
- Rails constants.
- Association names.
- Table names.
- Column names.

Schema identifiers such as table names, column names, Rails constants, and
association names remain allowed structured identifiers even when their literal
names contain credential-looking substrings such as `api_key` or
`password_digest`. They must still pass the relevant syntax/safe-token rules and
must not include values. Free-text diagnostic messages and metadata keys do not
get this exemption.

## Diagnostics

Diagnostic object fields:

- `diagnostic_id`
- `code`
- `severity`
- `phase`
- `scope`
- `subject_id`
- `message`
- `metadata`
- `artifact_refs`
- `remediation`

`metadata` must be sanitized and schema-closed per diagnostic code.

All diagnostic objects include every listed field. When no structured metadata is
available, `metadata` is `{}`. When no artifact reference applies,
`artifact_refs` is `[]`. When no remediation is known, `remediation` is `null`.
`artifact_refs[]` objects are closed and contain `artifact_kind` (`diagnostics`,
`er`, `class`, `render_plan`, or `stderr`), optional `domain_id` (`null` for
global), and optional project-root-relative `path`. `remediation`, when present,
is a closed object with `summary` and optional `steps[]`, all sanitized strings.

Per-code metadata schemas are intentionally small and closed:

- Config/output codes: `CONFIG_NOT_FOUND` has `config_path`; `CONFIG_SCHEMA_INVALID`
  has `config_path` and `field_path`; `CONFIG_DOMAIN_NOT_FOUND` has `domain_id`;
  `OUTPUT_DIRECTORY_INVALID` has `field_path` and `reason`.
- Domain/model codes: `DOMAIN_MODEL_NOT_FOUND` has `domain_id` and
  `ruby_constant`; `DOMAIN_MODEL_NOT_RENDERABLE` has `domain_id`,
  `ruby_constant`, and `renderability_reason`; `DOMAIN_EMPTY` has `domain_id`;
  `MODEL_TABLE_MISSING` has `domain_id`, `ruby_constant`, and `table_name`;
  `MODEL_PRIMARY_KEY_UNSUPPORTED` has `domain_id`, `ruby_constant`, and
  `table_name`.
- Rails load codes: `RAILS_LOAD_FAILED` and `RAILS_EAGER_LOAD_FAILED` have
  `exception_class`, `exception_summary`, and `backtrace` fixed to `null`.
- Connection/schema degradation codes: `MULTI_DB_UNSUPPORTED` has `domain_id`
  and `connection_context_ids[]`; `DB_METADATA_DEGRADED` has `domain_id`,
  `ruby_constant`, `metadata_kind`, and `reason`.
- Association omission codes have `domain_id`, `owner_constant`,
  `association_name`, and optional `target_constant`.
- `ASSOCIATION_MACRO_OMITTED` instead has `domain_id`, `owner_constant`,
  `association_name`, and required snake-case `association_macro`.
- Token/serialization/publish/internal codes: `SAFE_TOKEN_COLLISION` has
  `artifact_kind`, `domain_id`, `token_kind`, `base_safe_token`,
  `collision_subject_count`, and `resolved`; `MERMAID_SERIALIZATION_FAILED` has
  `artifact_kind`, `domain_id`, and `reason`; `OUTPUT_WRITE_FAILED` has
  `operation` and optional `path`; `INTERNAL_ERROR` has `exception_class`,
  `exception_summary`, and `backtrace` fixed to `null`.

Fields not listed for a diagnostic code are forbidden. Optional fields may be
omitted, but present fields must use the listed sanitized shape.

Closed diagnostic codes:

- `CONFIG_NOT_FOUND`
- `CONFIG_SCHEMA_INVALID`
- `CONFIG_DOMAIN_NOT_FOUND`
- `OUTPUT_DIRECTORY_INVALID`
- `DOMAIN_MODEL_NOT_FOUND`
- `DOMAIN_MODEL_NOT_RENDERABLE`
- `DOMAIN_EMPTY`
- `RAILS_LOAD_FAILED`
- `RAILS_EAGER_LOAD_FAILED`
- `MULTI_DB_UNSUPPORTED`
- `MODEL_TABLE_MISSING`
- `MODEL_PRIMARY_KEY_UNSUPPORTED`
- `ASSOCIATION_TARGET_UNRESOLVED`
- `ASSOCIATION_THROUGH_UNRESOLVED`
- `ASSOCIATION_SOURCE_UNRESOLVED`
- `ASSOCIATION_TARGET_NOT_RENDERABLE_OMITTED`
- `ASSOCIATION_POLYMORPHIC_OMITTED`
- `ASSOCIATION_SCOPED_OMITTED`
- `ASSOCIATION_COMPOSITE_KEY_OMITTED`
- `ASSOCIATION_KEY_COLUMN_MISSING`
- `ASSOCIATION_NON_PRIMARY_KEY_OMITTED`
- `ASSOCIATION_NAME_UNSUPPORTED_OMITTED`
- `ASSOCIATION_MACRO_OMITTED`
- `DOMAIN_RELATIONSHIP_OMITTED`
- `DB_METADATA_DEGRADED`
- `SAFE_TOKEN_COLLISION`
- `MERMAID_SERIALIZATION_FAILED`
- `OUTPUT_WRITE_FAILED`
- `INTERNAL_ERROR`

Diagnostic catalog:

| code | default_severity | default_exit_code | default_phase | default_scope | default_attachment | default_publication_effect |
|---|---|---:|---|---|---|---|
| `CONFIG_NOT_FOUND` | error | 2 | config | invocation | stderr diagnostics | pre-output fatal; no files |
| `CONFIG_SCHEMA_INVALID` | error | 2 | config | invocation | stderr diagnostics | pre-output fatal; no files |
| `CONFIG_DOMAIN_NOT_FOUND` | error | 2 | config | domain | stderr diagnostics | pre-output fatal; no files |
| `OUTPUT_DIRECTORY_INVALID` | error | 2 | output_setup | invocation | stderr diagnostics | pre-output fatal; no files |
| `DOMAIN_MODEL_NOT_FOUND` | error | 2 | domain_resolution | domain | diagnostics JSON | blocks selected artifacts |
| `DOMAIN_MODEL_NOT_RENDERABLE` | error | 2 | domain_resolution | model | diagnostics JSON | blocks selected artifacts |
| `DOMAIN_EMPTY` | error | 2 | domain_resolution | domain | diagnostics JSON | blocks selected artifacts |
| `RAILS_LOAD_FAILED` | error | 2 | rails_load | invocation | diagnostics JSON or stderr before output | blocks selected artifacts |
| `RAILS_EAGER_LOAD_FAILED` | error | 2 | rails_load | invocation | diagnostics JSON or stderr before output | blocks selected artifacts |
| `MULTI_DB_UNSUPPORTED` | error | 2 | schema_probe | domain | diagnostics JSON | blocks selected artifacts |
| `MODEL_TABLE_MISSING` | error | 2 | schema_probe | model | diagnostics JSON | blocks selected artifacts |
| `MODEL_PRIMARY_KEY_UNSUPPORTED` | error | 2 | schema_probe | model | diagnostics JSON | blocks selected artifacts |
| `ASSOCIATION_TARGET_UNRESOLVED` | warning | 0 | relationship_build | relationship | diagnostics JSON | omit relationship |
| `ASSOCIATION_THROUGH_UNRESOLVED` | warning | 0 | relationship_build | relationship | diagnostics JSON | omit relationship |
| `ASSOCIATION_SOURCE_UNRESOLVED` | warning | 0 | relationship_build | relationship | diagnostics JSON | omit relationship |
| `ASSOCIATION_TARGET_NOT_RENDERABLE_OMITTED` | warning | 0 | relationship_build | relationship | diagnostics JSON | omit relationship |
| `ASSOCIATION_POLYMORPHIC_OMITTED` | warning | 0 | relationship_build | relationship | diagnostics JSON | omit relationship |
| `ASSOCIATION_SCOPED_OMITTED` | warning | 0 | relationship_build | relationship | diagnostics JSON | omit relationship |
| `ASSOCIATION_COMPOSITE_KEY_OMITTED` | warning | 0 | relationship_build | relationship | diagnostics JSON | omit relationship |
| `ASSOCIATION_KEY_COLUMN_MISSING` | warning | 0 | relationship_build | relationship | diagnostics JSON | omit relationship |
| `ASSOCIATION_NON_PRIMARY_KEY_OMITTED` | warning | 0 | relationship_build | relationship | diagnostics JSON | omit relationship |
| `ASSOCIATION_NAME_UNSUPPORTED_OMITTED` | warning | 0 | relationship_build | relationship | diagnostics JSON | omit relationship |
| `ASSOCIATION_MACRO_OMITTED` | warning | 0 | relationship_build | relationship | diagnostics JSON | omit relationship |
| `DOMAIN_RELATIONSHIP_OMITTED` | warning | 0 | relationship_build | relationship | diagnostics JSON | omit relationship |
| `DB_METADATA_DEGRADED` | warning | 0 | schema_probe | domain | diagnostics JSON | weaken metadata evidence only |
| `SAFE_TOKEN_COLLISION` | warning or fatal | 0 or 3 | tokenization | artifact | diagnostics JSON | warning when suffix resolves; fatal when suffix exhaustion remains |
| `MERMAID_SERIALIZATION_FAILED` | error | 3 | serialization | artifact | diagnostics JSON | no `.mmd` or render plan published |
| `OUTPUT_WRITE_FAILED` | error | 4 | publish | invocation | diagnostics JSON or stderr | publish failed |
| `INTERNAL_ERROR` | error | 99 | internal | invocation | diagnostics JSON or stderr | abort invocation |

Categories:

- Config and output-directory pre-output fatal diagnostics exit `2` and write
  sanitized diagnostics JSON to stderr only.
- Rails load/eager-load, multi-DB, table, and PK errors exit `2`.
- Mermaid serialization and unresolved safe-token exhaustion exit `3`.
- Output write failure exits `4`.
- Internal error exits `99`.
- Warning diagnostics default to exit `0` unless `--fail-on-warning` promotes
  warnings to invocation exit `1`.

Warning diagnostic `default_exit_code: 0` is not an exemption from invocation
exit policy. `SAFE_TOKEN_COLLISION`, `DB_METADATA_DEGRADED`, and other warnings
can still make the invocation exit `1` when `--fail-on-warning` is present.

### DB_METADATA_DEGRADED

Emit `DB_METADATA_DEGRADED` when selected-domain metadata needed only for DB FK
existence, FK nullability, unique-index, or cardinality-strength evidence is
unavailable, adapter-degraded, permission-limited, or internally inconsistent
while required table, primary-key, and column metadata remain usable.

It attaches to the relevant domain with:

- `phase: schema_probe`
- `scope: domain`
- `severity: warning`
- `default_exit_code: 0`

Degraded metadata must only weaken cardinality evidence. It must not create,
omit, or strengthen relationship edges by itself.

## Artifacts And Publishing

Artifact names:

- `global.diagnostics.json`
- `<domain>.diagnostics.json`
- `<domain>.er.mmd`
- `<domain>.er.render_plan.json`
- `<domain>.class.mmd`
- `<domain>.class.render_plan.json`

Diagnostics file placement:

- Invocation-scope diagnostics are written only to `global.diagnostics.json`
  after the output directory is known and safe.
- Domain, model, relationship, and artifact diagnostics are written only to the
  matching `<domain>.diagnostics.json`.
- A diagnostic must not be duplicated across global and domain diagnostics.
- Empty diagnostics files are omitted.
- Render plans may reference diagnostic IDs from `global.diagnostics.json` or
  the matching domain diagnostics file only.

Diagnostics JSON top-level shape:

```json
{
  "schema_version": 1,
  "scope": "global",
  "domain_id": null,
  "diagnostics": [],
  "digest_sha256": "lowercase-64-hex"
}
```

For `<domain>.diagnostics.json`, `scope` is `"domain"` and `domain_id` is the
configured domain ID string, for example `"core"`. For `global.diagnostics.json`
and pre-output fatal stderr diagnostics, `scope` is `"global"` and `domain_id` is
JSON `null`.

Render-plan JSON top-level shape:

```json
{
  "schema_version": 1,
  "artifact_kind": "er|class",
  "domain_id": "core",
  "direction": "LR",
  "entities": [],
  "relationships": [],
  "comments": [],
  "diagnostic_ids": [],
  "digest_sha256": "lowercase-64-hex"
}
```

Render-plan `entities[]`, `relationships[]`, and `comments[]` are closed
objects produced from normalized IR. Each object must carry only canonical
structured identifiers, safe tokens, Mermaid-facing labels/comments after
sanitization, and deterministic ordering keys. They must not include raw Rails
objects, absolute paths, timestamps, process IDs, random seeds, or raw exception
data.

Render-plan attributes carry a Mermaid-facing `type` string for serializers.
The field is lowercase ASCII text matching `[a-z][a-z0-9_]*`. Unknown,
unsupported, or unavailable DB/Rails attribute types are projected as
`unknown`. Mermaid serializers must use this render-plan `type` field for
attribute output and must not look back to IR, schema metadata, or Rails objects
to infer attribute types.

Render-plan safe tokens are final diagram tokens. The render-plan generator owns
safe-token generation, and the Mermaid serializer must reuse those tokens without
re-tokenizing. Token collision scope uses the render plan's final artifact kind
(`er` or `class`).

Rails constants, association names, table names, and column names are structured
identifiers. Render-plan builder normalization may remove NUL bytes, replace
control characters with spaces, collapse whitespace, and apply deterministic
schema-safe fallbacks, but it must not apply free-text credential-key redaction
to valid structured identifier substrings such as `ApiKey`, `api_key`,
`password_digest`, or `access_token`. Free-text redaction remains required for
comments and diagnostic free-form text.

Pre-output fatal publish policy:

- `CONFIG_NOT_FOUND`, `CONFIG_SCHEMA_INVALID`, `CONFIG_DOMAIN_NOT_FOUND`, and
  `OUTPUT_DIRECTORY_INVALID` write one sanitized diagnostics JSON object to
  stderr only.
- Pre-output fatal diagnostics write no files.

Atomic publish policy:

1. Validate output directory.
2. Re-check the resolved output directory path immediately before creating the
   temporary directory; refuse symlink targets or paths that now resolve outside
   the project root.
3. Create a temporary directory inside the already-validated output directory
   using no-follow filesystem operations where the platform supports them.
4. Generate all selected outputs into the temporary directory.
5. Validate JSON schemas.
6. Validate every render-plan `diagnostic_ids[]` exists in global or matching
   domain diagnostics.
7. Invocation-scope fatal or error diagnostics block all selected `.mmd` and
   render-plan artifacts.
8. Domain, model, relationship, and artifact fatal or error diagnostics block
   only the matching domain's `.mmd` and render-plan artifacts; unaffected
   selected domains still publish when they have no fatal or error diagnostics.
9. Publish non-empty diagnostics files for scopes that have diagnostics.
10. Publish `.mmd` and render-plan JSON only for unblocked selected domains.
11. Reconcile managed artifacts atomically within the already-validated output
    directory: the invocation's managed artifact set replaces the previous
    managed set for the selected domains, and stale managed `.mmd`, render-plan,
    and diagnostics files for those selected domains are removed.
12. Re-check final target paths during replacement, refuse symlink targets, and
    perform replacement inside the validated output directory.
13. Remove the temporary directory on success or failure.

Publish gating:

- A single invocation-scope fatal or error diagnostic prevents all selected
  `.mmd` and render-plan artifacts for that invocation from being published.
- A domain-scoped fatal or error diagnostic prevents only that domain's `.mmd`
  and render-plan artifacts from being published.
- Diagnostics may still be published after the output directory is known and
  safe.

## Mermaid Rendering

ER rules:

- Use safe ASCII tokens.
- Use sanitized comments.
- Relationship labels are mandatory and non-empty.
- ER left/right markers are asymmetric where Mermaid requires it.
- Use Mermaid ER native `PK`/`FK` syntax.
- Emit no empty blocks for `attributes: none`.
- Use line style `..`, not `--`.

ER cardinality marker mapping:

| cardinality | left marker | right marker |
|---|---|---|
| `0..1` | `|o` | `o|` |
| `1..1` | `||` | `||` |
| `0..many` | `}o` | `o{` |
| `1..many` | `}|` | `|{` |

P0 direct `belongs_to` never emits `1..many` because it cannot prove every
target has at least one owner.

Direct `belongs_to` cardinality evidence:

- Owner endpoint is `0..1` only when a total unique index on the single owner FK
  is confirmed.
- Otherwise owner endpoint is `0..many`.
- Target endpoint is `1..1` only when DB FK exists and owner FK is non-nullable.
- Otherwise target endpoint is `0..1`.
- Unknown or degraded metadata never strengthens cardinality.

Direct `has_many` / `has_one` cardinality evidence (P1-03):

- The declaration owner endpoint is `1..1` only when a DB FK exists from the
  associated target and that FK column is non-nullable; otherwise it is `0..1`.
- The associated target endpoint is `0..many` for `has_many` and `0..1` for
  `has_one`.
- `has_one` represents the Active Record singular bound even when a unique DB
  index does not enforce it.

P1-04 normalizes those bounds to canonical FK orientation: the holder endpoint
is `0..1` when any group candidate is `has_one` or the FK has a total plain
unique index, otherwise `0..many`; the referenced endpoint is `1..1` only with
DB-FK and non-null evidence, otherwise `0..1`.

ClassDiagram relationship syntax:

```text
OWNER "<owner multiplicity>" --> "<target multiplicity>" TARGET : <label>
```

ClassDiagram attributes use class member syntax and do not emit ER key tags:

```text
+<type> <label>
```

For example, `+integer id` and `+integer account_id` are valid classDiagram
attributes; `integer id PK` and `integer account_id FK` are ER-only syntax.

Class multiplicity mapping:

| cardinality | classDiagram multiplicity |
|---|---|
| `0..1` | `0..1` |
| `1..1` | `1` |
| `0..many` | `0..*` |
| `1..many` | `1..*` |

Runtime `rails-mmd` does not require Mermaid CLI validation in P0.

## Safe Tokens

Safe-token algorithm:

1. Stringify structured source value.
2. Unicode normalize to NFKD.
3. Replace Ruby `::` with `_`.
4. Insert `_` at CamelCase lower-to-upper boundaries.
5. Insert `_` at acronym-to-word boundaries.
6. Replace runs outside ASCII letters/digits with `_`.
7. Drop remaining non-ASCII codepoints.
8. Collapse repeated `_`.
9. Trim leading and trailing `_`.
10. Uppercase.
11. If empty, use `X`.
12. If first char is a digit, prefix `X_`.
13. Check uniqueness within collision scope.

Examples:

| source | safe token |
|---|---|
| `Admin::User` | `ADMIN_USER` |
| `HTTPResponseCode` | `HTTP_RESPONSE_CODE` |
| `注文Line` | `LINE` |
| `order_item` | `ORDER_ITEM` |
| `123Order` | `X_123_ORDER` |
| `!!!` | `X` |

Collision scope fields are `{artifact_kind, domain_id, token_kind}`:

- `artifact_kind`: `er` or `class`.
- `domain_id`: configured domain ID or `global`.
- `token_kind`: `entity`, `attribute`, `relationship`, `diagnostic`, or
  `comment`.

Safe-token collision digest input is RFC 8785/JCS canonical JSON bytes of:

```json
{
  "scope": {
    "artifact_kind": "<artifact-kind>",
    "domain_id": "<domain-id-or-global>",
    "token_kind": "<token-kind>"
  },
  "subject_identity": "<structured subject identity>",
  "base_safe_token": "<pre-suffix safe token>"
}
```

The input is encoded as UTF-8.

Collision suffix:

1. Compute SHA-256 over canonical collision digest input.
2. Encode the digest as uppercase hexadecimal.
3. Append `_H` plus the first 12 hex characters to the base token for every
   colliding subject in the scope.
4. Use the suffixed value as the final safe token.

Suffix-collision retry:

- If suffixed tokens still collide within the same scope, extend affected
  suffixes by 4 additional hex characters at a time.
- Continue up to the full 64 hex characters.
- If collision remains at 64, emit fatal `SAFE_TOKEN_COLLISION` and do not
  publish `.mmd` or render-plan artifacts.

`SAFE_TOKEN_COLLISION` uses the same code for warning and fatal outcomes. Emit it
as a warning when two or more distinct structured subjects produce the same
scoped base safe token and suffixing resolves the final tokens; set metadata
`resolved: true`. Emit it as fatal with exit `3` only when suffixing cannot
resolve a collision after full 64-hex expansion; set `resolved: false` and do not
publish `.mmd` or render-plan artifacts.

## Determinism And Digests

Ordering:

- Domains by domain ID ASCII order unless `--domain` selects one.
- Entities by `entity_id`.
- Attributes by attribute class `pk` before `fk`, then `attribute_id`.
- Relationships by `relationship_id`.
- Diagnostics by `severity_rank`, `code`, `subject_id` or empty string, then
  `diagnostic_id`. Severity rank is `fatal` = 0, `error` = 1, `warning` = 2.
- Artifacts publish diagnostics first, then ER files, ER render plan, class
  files, and class render plan per domain ID.

JSON serialization for digests uses RFC 8785/JCS canonical object key ordering.
Emitted pretty JSON may be human-readable but must preserve deterministic array
ordering.

Render-plan and diagnostics digest fields are named `digest_sha256`.

Digest value:

- SHA-256 lowercase 64-character hex.
- Computed over RFC 8785/JCS canonical JSON bytes of normalized payloads.
- Excludes generated timestamps, absolute paths, temp paths, process IDs,
  random seeds, raw exception backtraces, and any machine-local values.

Canonical JSON implementation intent: use the `json-canonicalization` gem for
JCS/RFC 8785 canonical bytes rather than a custom object sorting routine.

## Future implementation sequence

This is a non-implementation reference. It lists future P0 implementation
slices in order and does not authorize implementation in this setup issue.

1. Config loader and schema validation.
2. Rails boot and eager load.
3. Model inventory.
4. Domain resolution.
5. Selected schema probe and connection guard.
6. Relationship builder.
7. IR normalization and safe tokens.
8. Render-plan generation.
9. Mermaid serialization.
10. Diagnostics and exit policy.
11. Redaction.
12. Atomic artifact publishing.
13. CLI integration.
