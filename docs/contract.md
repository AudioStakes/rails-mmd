# rails-mmd Contract

This document defines the current generation behavior. The [usage guide](usage.md)
owns command examples and configuration defaults; the
[association support matrix](active-record-association-support.md) summarizes
compatibility limits. The JSON files in [schemas](../schemas/) define the exact
closed payload shapes. Update those sources and their executable specs together
when behavior changes.

## Supported Scope

`rails-mmd` boots and eager-loads a trusted Rails application in its own bundle,
selects exact configured Active Record base models, reads their schema metadata,
and writes deterministic Mermaid ER and class diagrams. It supports direct
`belongs_to`, `has_many`, and `has_one`, inferred-source through paths,
selected-target polymorphic associations, and verified HABTM join tables under
the eligibility rules below.

Domains are configured manually. Each domain has its own selected model set,
connection guard, diagnostics, and artifacts. Output attributes are primary and
rendered foreign keys (`keys`), or no attributes (`none`).

## Excluded Scope

There is no automatic domain, depth expansion, glob/regex model selection,
`.erdconfig` compatibility, content/unique-key attribute mode, generation cache,
or runtime Mermaid CLI. STI subclasses, delegated-type specialization, composite
keys, scoped association rendering, cross-domain edges, and multiple connection
contexts within one domain are unsupported. Association options and behavior
metadata outside the supported cases are not inferred.

The declared Ruby range and actual Ruby/Rails test pairs are separate claims:
see [compatibility](../README.md#compatibility-and-limits). The executable pair
list is [matrix.yml](../fixtures/rails_matrix/matrix.yml); each series lockfile
owns its exact Rails patch and dependency versions.

## Configuration And CLI

The only generation command is:

```text
rails-mmd generate --config PATH --output-dir DIR --domain ID --format er|class|both --fail-on-warning
```

The resolved YAML file is required. Loading uses safe YAML without ERB or
aliases, and does not load application constants. `version: 1` and nonempty
`domains` are required; unknown keys and invalid values fail schema validation.
Includes and excludes contain exact Ruby constant names. Domain IDs match
`\A[a-z][a-z0-9]*(?:_[a-z0-9]+)*\z`.

CLI output-directory and format values override config values, which override
the defaults in the [usage reference](usage.md#configuration-reference).
`--domain` selects one configured domain; omitting it selects all domains.
`--fail-on-warning` defaults to false and changes the exit status after normal
publication. Unknown options, extra arguments, missing option values, and
invalid boolean arguments fail before generation with CLI exit `1`.

Output directories must be nonempty project-root-relative paths using ASCII
letters, digits, `.`, `_`, `-`, and `/`. Lexical normalization may resolve `.`
and `..` segments but must not produce the project root or escape it. Absolute,
drive, UNC, backslash, NUL, and unsupported-character forms are rejected.
Existing symlinked directories are accepted only when their real path stays
within the application root; managed artifact targets themselves cannot be
symlinks or non-regular files.

## Stage Boundaries

| Stage | Responsibility | Output |
|---|---|---|
| Config | Validate YAML, CLI overrides, and selected domain IDs | Resolved config or pre-output diagnostics |
| Rails loader | Validate target bundle, load `config/environment.rb`, eager-load app | Load diagnostics |
| Model inventory | Discover named constant-backed models without schema queries | Selection and renderability records |
| Domain resolver | Resolve includes/excludes and select renderable models | Domain model sets and diagnostics |
| Schema probe | Guard connections, read selected model and HABTM table metadata | Normalized metadata and diagnostics |
| Relationship builder | Inspect reflections and normalize eligible associations | Canonical edges and omission diagnostics |
| IR builder | Project entities, key attributes, and relationships | Internal version-1 IR |
| Render-plan builder | Assign safe tokens and Mermaid-facing labels/types | Version-1 ER/class render plans |
| Mermaid serializer | Serialize validated plans without Rails/DB access | `.mmd` text or serialization diagnostics |
| Publisher | Validate scope, schemas and references, then replace managed files | Artifacts or publication diagnostics |

The IR is internal and is not published. Render plans are the structured output
contract. Database access stays in schema probing; relationship construction
receives normalized metadata, and serialization consumes only render plans.

The Rails loader requires the application's own bundle. An alias of the same
application directory is accepted; a different application's bundle or an
alternate Gemfile with a different lockfile is rejected. Booting executes
application Ruby code and initializers; this is not a sandbox.

## Inventory, Domains, And Schema

Inventory includes named Active Record descendants only when their Ruby constant
resolves back to the same class. Anonymous, blank-named, or non-resolvable
descendants are ignored. Inventory does not read table existence, columns,
indexes, or foreign keys. A renderable model is concrete, is its own
`base_class`, and exposes usable table-name and connection-context information.

For each selected domain, resolve exact includes and excludes first. Missing
constants produce `DOMAIN_MODEL_NOT_FOUND`; abstract models, STI subclasses, or
other non-renderable records produce `DOMAIN_MODEL_NOT_RENDERABLE`, even when
named in exclusions. Subtract exclusions only after validating both lists.
An empty final set produces `DOMAIN_EMPTY`. No related model is auto-included.

The schema probe visits only selected entities and hidden join tables requested
by their HABTM reflections. Required table/column metadata failures produce
`MODEL_TABLE_MISSING`; a missing or non-scalar primary key produces
`MODEL_PRIMARY_KEY_UNSUPPORTED`.

Each domain must select exactly one connection context. Context comparison
uses the canonical JSON representation of Rails config name, role, shard,
adapter, database identifier, host, port, and username. Different config names,
roles or shards remain different contexts even when they address the same
database. Passwords and raw connection strings are not context fields. Contexts
outside a selected domain do not participate in its guard. Multiple selected
contexts produce `MULTI_DB_UNSUPPORTED`; identifiers are sanitized before they
are emitted in diagnostics.

Unavailable or inconsistent optional FK/index metadata produces
`DB_METADATA_DEGRADED` while preserving usable rows. This must only weaken
cardinality evidence; it must not create or omit relationships by itself.
Primary key, column, and table metadata remain mandatory. Only an exact total
plain unique index proves uniqueness; partial or expression indexes do not.

## Relationship Eligibility And Identity

Every emitted relationship uses selected, renderable entities within one domain.
Association names must match `\A[a-z][a-z0-9]*(?:_[a-z0-9]+)*[!?=]?\z`.
The optional trailing `?`, `!`, or `=` is removed from the rendered label.
Unsupported names produce `ASSOCIATION_NAME_UNSUPPORTED_OMITTED`.

Scopes are detected from reflection metadata without executing scope procs or
association readers. A target model's `default_scope` alone does not make an
otherwise unscoped direct reflection scoped. All relationship families retain
specific omission diagnostics for failed eligibility; unsupported macros use
`ASSOCIATION_MACRO_OMITTED`.

### Direct associations

Direct, unscoped, non-polymorphic `belongs_to`, `has_many`, and `has_one` require
one existing FK column and a scalar referenced key equal to the referenced
entity's actual primary key. `belongs_to` holds its FK on the declaring model;
direct has-associations hold it on the target. Explicit scalar `foreign_key`,
`class_name`, and `primary_key` options are eligible when those rules still hold.

Group all supported declarations by physical tuple and orient every edge from
FK holder to referenced entity. This is independent of explicit, automatic,
absent, or disabled `inverse_of`. One-sided declarations, aliases, and self
joins use the same rule. The public ID is:

```text
relationships/<holder_table>/<fk_column>/<referenced_table>/<primary_key>
```

Choose the label by `belongs_to`, `has_one`, `has_many`, then lexical declaration
ID. The holder endpoint is `0..1` when any eligible candidate is `has_one` or
there is an exact total plain unique index on the FK; otherwise it is
`0..many`. The referenced endpoint is `1..1` only with a matching database FK
and non-nullable holder FK; otherwise it is `0..1`. `has_one` therefore retains
its Active Record singular bound even without a unique database index.

### Through associations

Unscoped, non-polymorphic `has_many :through` and `has_one :through` require a
Rails-inferred source. Every intermediate and final model in the complete chain
must resolve, be renderable, and be selected in the same domain. Explicit
`source:`, `source_type:`, polymorphic hops, and scoped chains are omitted.
Missing through/intermediate resolution uses `ASSOCIATION_THROUGH_UNRESOLVED`;
missing, ambiguous, or unreadable source chains use
`ASSOCIATION_SOURCE_UNRESOLVED`.

Normalize `collect_join_chain` once into owner-forward order and replace its
outer declaration hop with the terminal source-reflection name. Preserve every
hop for nested paths. The ID is:

```text
relationships/<owner_table>/through/<path...>/<target_table>
```

Direct physical edges remain alongside these semantic edges. Equal normalized
paths collapse to one edge; distinct paths to the same target remain distinct.
Label priority is `has_one`, `has_many`, then lexical association name. The owner
endpoint is `0..many`; the target is `0..1` for `has_one` and `0..many` for
`has_many`. Semantic through edges add no synthetic FK attributes.

### Polymorphic associations

Inventory reflections in two passes. A direct, unscoped polymorphic
`belongs_to` root is required; never call its `klass`. Its scalar holder columns
must exist and use the default `<interface>_id` and `<interface>_type` names.
Custom/composite keys, STI expansion, delegated-type specialization, and
polymorphic through/source-type resolution are unsupported.

Discover targets only from selected direct, unscoped `has_many` or
`has_one ..., as:` reflections. Interface, fixed child model, id/type columns,
and the candidate owner's actual primary key must match the root. Emit one edge
per concrete target:

```text
relationships/<holder_table>/polymorphic/<interface>/<id_column>/<type_column>/<target_table>
```

Orientation and label come from the root. Canonicalize inverse aliases by
`has_one`, `has_many`, then lexical association name. Each edge's target bound
is `0..1`; its holder bound is `0..1` for the selected canonical `has_one`
inverse or an exact total plain unique index on the id/type pair, otherwise
`0..many`. One candidate's singular declaration cannot strengthen another
target's bound. Both holder columns project as FK attributes.

Zero matching targets produces `ASSOCIATION_POLYMORPHIC_TARGETS_UNRESOLVED`.
Conflicting or unsupported inverse declarations retain
`ASSOCIATION_POLYMORPHIC_OMITTED` without suppressing valid candidates. An
inverse without a root does not invent a relationship. Scoped roots and inverses
retain `ASSOCIATION_SCOPED_OMITTED`.

### HABTM associations

Unscoped `has_and_belongs_to_many` requires selected endpoints and scalar
reflected endpoint primary keys equal to the actual entity keys. Explicit options
that resolve to those actual keys remain eligible. The join table and two
distinct scalar join-column names must be valid structured identifiers.

`SchemaProbe` reads the hidden table. It must exist, have no primary key, and
contain exactly the two join columns, without payload or timestamp columns.
Unreadable/malformed table metadata produces `ASSOCIATION_JOIN_TABLE_INVALID`
with reason `unresolved`, `primary_key_present`, `join_column_missing`,
`extra_columns`, or `ambiguous_columns`.

Normalize endpoint tuples `(entity_id, join_column)` lexically. One-sided,
reciprocal, alias, custom table/column, and self-HABTM declarations share the
same physical signature and one ID:

```text
relationships/<left_table>/habtm/<join_table>/<left_column>/<right_table>/<right_column>
```

Prefer a label declared by the normalized left endpoint, then lexical association
name. Both bounds are always `0..many`, irrespective of join-table indexes or
FKs. The hidden table is not rendered as an entity and adds no endpoint key
attributes. An invalid declaration does not suppress a valid alias; an invalid
table prevents every edge that requires that table.

## IR And Render Plans

IR, render plans, and diagnostics documents use `schema_version: 1`. Entity IDs
are `entities/<table>`; attribute IDs are
`entities/<table>/attributes/<column>`. Public relationships contain normalized
endpoints, association label, cardinalities, and their family-specific ID;
reflection objects and internal candidate evidence are not serialized.

With `attributes: keys`, project the actual primary key and columns referenced
by emitted direct/polymorphic relationships. Deduplicate shared PK/FK column
identities, with primary-key role taking precedence. With `attributes: none`,
project no attributes. IR carries source DB/Rails types; render plans normalize
them to supported lowercase Mermaid types, falling back to `unknown`.
Serializers use that final type without querying IR, Rails, or the database.

Render plans own final safe tokens, labels, comments, and diagnostic references.
Builders derive relationship endpoints from selected entities. Attribute
identities are deduplicated during projection and validated for uniqueness.
Each diagnostic reference must belong to the global document or the matching
domain; a reference to another domain is invalid. Exact field sets and
valid/invalid examples live in the JSON schemas and contract fixtures.

## Redaction

Sanitize free-form diagnostic messages and metadata, exception summaries,
remediation, stderr diagnostics, Mermaid comments, and displayed paths before
publication. The redactor masks credential assignments and URL credentials,
known environment values of at least four characters, and unsafe absolute path
evidence. Project-contained paths may become relative; drive/UNC and external
paths are redacted. Mermaid free text also removes control characters and URLs.

Exception metadata contains the class name, sanitized summary, and
`backtrace: null`; raw backtraces are never published. Schema-closed structured
identifiers follow syntax validation instead of free-text key redaction.
Valid names such as `ApiKey`, `api_key`, `password_digest`, and `access_token`
must remain intact as identifiers without carrying credential values. Invalid
Mermaid-facing identifiers normalize to the deterministic `X` fallback.

Redaction does not anonymize the schema or control output/side effects from
application initializers. Generated artifacts intentionally contain model,
table, column, and relationship names and can contain sanitized connection
identifiers. See [SECURITY.md](../SECURITY.md) before sharing artifacts.

## Diagnostics

Every diagnostic includes `diagnostic_id`, `code`, `severity`, `phase`, `scope`,
`subject_id`, `message`, `metadata`, `artifact_refs`, and `remediation`.
Metadata is required, code-specific, and closed by
[diagnostics.schema.json](../schemas/diagnostics.schema.json). Artifact references
require a known `artifact_kind` and a `domain_id` field (nullable for global
references); a project-relative `path` is optional. Remediation is either null
or a closed sanitized summary/steps object.

Runtime severity, phase, and scope defaults live in
[`diagnostic_defaults.json`](../schemas/diagnostic_defaults.json). Schema fixtures
remain test data rather than a runtime dependency.

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
| `ASSOCIATION_POLYMORPHIC_TARGETS_UNRESOLVED` | warning | 0 | relationship_build | relationship | diagnostics JSON | omit polymorphic group |
| `ASSOCIATION_JOIN_TABLE_INVALID` | warning | 0 | relationship_build | relationship | diagnostics JSON | omit relationship |
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

Config/output-setup failures exit `2` before writing files. Other blocking
diagnostics use the catalog's exit category; when several occur, the highest
numeric category wins. Warnings normally exit `0`; `--fail-on-warning` changes
that to `1` without changing publication. A resolved safe-token collision is a
warning; exhausted collision resolution is fatal with exit `3`.

## Artifacts And Publishing

Managed names are `global.diagnostics.json`, `<domain>.diagnostics.json`,
`<domain>.er.mmd`, `<domain>.er.render_plan.json`, `<domain>.class.mmd`, and
`<domain>.class.render_plan.json`. Empty diagnostics documents are omitted.
Invocation diagnostics appear only in the global document; other scopes appear
only in their matching domain document. Diagnostics are never duplicated across
those documents.

Pre-output fatal diagnostics (`CONFIG_NOT_FOUND`, `CONFIG_SCHEMA_INVALID`,
`CONFIG_DOMAIN_NOT_FOUND`, `OUTPUT_DIRECTORY_INVALID`) write one sanitized
diagnostics JSON object to stderr and no files. Its document scope is `global`
and `domain_id` is null. Published domain documents use scope `domain` and the
configured ID. Successful/warning-only generation is silent on stdout/stderr.

Atomic publish policy:

1. Resolve the output directory and re-check containment before writes.
2. Validate schemas, artifact identities, and all diagnostic references.
3. Invocation-scoped errors/fatals block every selected domain's Mermaid and
   render plans. Other errors/fatals block only their matching domain.
4. Build a replacement plan containing nonempty diagnostics and unblocked
   artifacts for the selected domains and requested formats.
5. Stage files inside the validated output directory. Re-check containment and
   reject symlink/non-regular managed targets before replacement.
6. Back up existing managed files for selected domains and the global diagnostic
   file, then replace them. This removes stale managed files for that scope;
   unselected domains and unrelated/lookalike filenames are preserved.
7. If replacement fails, attempt rollback and report `OUTPUT_WRITE_FAILED`.
   Publication errors can fall back to sanitized stderr. When rollback also
   fails, retain unrestored originals in private `.rails-mmd-backup-*`
   directories and direct the user to inspect them before retrying.

Replacement is staged with rollback; it is not a database transaction or a
guarantee that concurrent readers observe the whole multi-file set at once.
Recovery instructions are in the [usage guide](usage.md#troubleshooting).

## Mermaid Rendering

ER output uses ASCII safe tokens, nonempty labels, non-identifying `..` lines,
and native `PK`/`FK` attribute tags. `attributes: none` emits standalone entities,
not empty attribute blocks. Class attributes use `+<type> <label>` without ER
key tags; relationships use:

```text
OWNER "<owner multiplicity>" --> "<target multiplicity>" TARGET : <label>
```

| Cardinality | ER left marker | ER right marker | Class multiplicity |
|---|---|---|---|
| `0..1` | `\|o` | `o\|` | `0..1` |
| `1..1` | `\|\|` | `\|\|` | `1` |
| `0..many` | `}o` | `o{` | `0..*` |
| `1..many` | `}\|` | `\|{` | `1..*` |

The serializer accepts `1..many`, but current relationship builders do not emit
it: association declarations do not prove that every referenced row has owners.
There is no runtime Mermaid CLI or hosted rendering request.

## Safe Tokens

Stringify the structured source, normalize Unicode to NFKD, replace Ruby `::`
with `_`, split lower-to-upper and acronym-to-word boundaries, and replace runs
outside ASCII letters/digits with `_`. Remove remaining non-ASCII characters,
collapse/trim underscores, and uppercase. Empty results become `X`; results
starting with a digit get `X_` prefixed. For example, `Admin::User` becomes
`ADMIN_USER`, `HTTPResponseCode` becomes `HTTP_RESPONSE_CODE`, and `123Order`
becomes `X_123_ORDER`.

Collision scope is `(artifact_kind, domain_id, token_kind)`, with artifact kind
`er` or `class` and token kind `entity`, `attribute`, `relationship`, `diagnostic`,
or `comment`. Compute SHA-256 over UTF-8 RFC 8785/JCS canonical JSON of:

```json
{
  "scope": {
    "artifact_kind": "<artifact-kind>",
    "domain_id": "<domain-id>",
    "token_kind": "<token-kind>"
  },
  "subject_identity": "<structured subject identity>",
  "base_safe_token": "<pre-suffix safe token>"
}
```

Append `_H` and the first 12 uppercase digest hex characters to every colliding
subject's base token. Reserve non-colliding tokens before suffixing, and reject
suffix candidates that collide with any reserved token. Extend affected suffixes
by four hex characters until unique, up to 64. Emit `SAFE_TOKEN_COLLISION` with
`resolved: true` when resolved, or fatal `resolved: false` when exhausted.
The serializer reuses final tokens without re-tokenizing.

## Determinism And Digests

Selected domains follow configuration order unless `--domain` selects one.
Within each domain, sort entities by `entity_id`, attributes by primary-key role
before foreign-key role then `attribute_id`, and relationships by
`relationship_id`. Sort diagnostics by severity (`fatal`, `error`, `warning`),
code, subject ID or empty string, then diagnostic ID. Render-plan comments and
diagnostic references also use deterministic ID order. Publish diagnostics
before ER files/plans and class files/plans within each selected domain.

`digest_sha256` is lowercase 64-character SHA-256 over RFC 8785/JCS canonical
JSON, implemented by `json-canonicalization`. Normalize the payload with
`digest_sha256: null` before computing its digest, then replace that field with
the digest. Pretty-printed output preserves the same deterministic array order.
Generated timestamps, process IDs, random seeds, raw backtraces, and machine-local
paths are not artifact fields.
