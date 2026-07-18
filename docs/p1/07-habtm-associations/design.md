# P1-07 HABTM Associations Design

Status: design complete and reviewed

## Decisions

### Schema-probe boundary

- Add `SchemaProbe::JoinTable` with `table_name`, `columns`, and `primary_key`.
- Add optional `join_tables` to the keyword-initialized
  `SchemaProbe::DomainResult`; existing callers may omit it.
- After selected entities are probed, inspect only each selected model's public
  HABTM reflections and safely collect resolved join-table names.
- Probe each table once through the selected model's already validated
  connection using `data_source_exists?`, `columns`, and `primary_key`.
- Missing, unresolved, or unreadable tables are absent from the cache. The
  relationship phase owns the association-scoped warning.
- `RelationshipBuilder` receives only normalized metadata and never reads a raw
  database connection.

### Reflection eligibility

- Route macro `:has_and_belongs_to_many` to a dedicated builder before through,
  direct-has, or generic-macro classification.
- Require an unscoped, safely named declaration.
- Resolve `klass` safely, then require a renderable selected same-domain target.
- Safely read scalar `join_table`, `foreign_key`, and
  `association_foreign_key` after target resolution. All three must satisfy the
  repository's structured table/column identifier rules before entering a
  public ID.
- Owner and target already have scalar actual primary keys by `SchemaProbe`.
  No custom/non-primary association-key inference is added.
- Require distinct join columns and a cached join table whose primary key is
  nil and whose complete column-name set equals the two join columns.
- One-sided, reciprocal, aliases, custom scalar table/key names, `class_name`,
  and self-HABTM with distinct columns all use the same path.

### Relationship identity and projection

- Add internal `relationship_kind: :habtm` and `join_table_name`; keep public
  schemas unchanged.
- Normalize endpoint tuples `(entity_id, join_column)` lexically.
- Internal physical key:
  `habtm|<join_table>|<left_entity>|<left_column>|<right_entity>|<right_column>`.
- Public ID:
  `relationships/<left_table>/habtm/<join_table>/<left_column>/<right_table>/<right_column>`.
- Public owner/target endpoints are normalized left/right; both cardinalities
  are always `0..many`.
- HABTM carries no `foreign_key_holder_entity_id`, `foreign_key_column`, or
  `foreign_type_column`. `IrBuilder` therefore adds no synthetic entity key
  attributes.
- Deduplicate by physical key. Choose the canonical declaration by preferring a
  declaration owned by the normalized left endpoint, then lexical association
  name. Reflection enumeration order never participates.
- A declaration-local invalid alias emits its own warning while a valid
  declaration with the same signature still publishes. A table-global shape
  failure prevents every edge using that table.

### Diagnostics

- Reuse target/domain, scope, unsafe-name, composite-key, and non-primary-key
  omission paths.
- Add one closed warning code: `ASSOCIATION_JOIN_TABLE_INVALID`.
- Add a dedicated closed metadata shape rather than extending the shared
  association shape, which forbids extra properties. Its required fields are:
  `domain_id`, `owner_constant`, `association_name`, optional
  `target_constant`, `join_table`, and `reason`.
- Closed reasons:
  `unresolved`, `primary_key_present`, `join_column_missing`, `extra_columns`,
  and `ambiguous_columns`.
- Subject, phase, scope, severity, exit behavior, and attachment match other
  relationship-build omission warnings.

### Deferred shapes

- Scoped/owner-dependent HABTM remains a scoped omission.
- Composite join columns, custom association primary keys, STI expansion,
  cross-domain/multi-DB targets, and join tables with payload columns remain
  deferred.
- Rails 8.1 `deprecated` metadata is not rendered.
- Synthetic private `has_many :through` reflections are never inventoried.

## Exact Rails matrix oracle

- Keep `Author has_and_belongs_to_many :tags` and add reciprocal
  `Tag has_and_belongs_to_many :authors`.
- Add selected `Tag`, `tags`, and id-less `authors_tags` with exactly
  `author_id` and `tag_id`.
- Remove the former HABTM macro omission expectation.
- Extend the exact relationship expectation with one edge:
  `relationships/authors/habtm/authors_tags/author_id/tags/tag_id`, owner
  `AUTHOR`, target `TAG`, label `tags`, and `0..many` on both ends.
- The existing exact relationship validator compares ID, endpoints, label, and
  cardinalities. Add a task-level fake-artifact regression whose only missing
  expected item is the HABTM edge.
- The reciprocal fixture is the order-invariance proof: reverse public
  declaration inventory in an isolated spec and require the same exact
  projection as the real reciprocal app.
- Run the same fixture on Rails 7.2.3.1 / Ruby 4.0.6 and Rails 8.1.3 / Ruby
  3.3.12 and 4.0.6.

## Public TDD seams

- `SchemaProbe#probe` domain join-table cache.
- `RelationshipBuilder#build` relationships and diagnostics.
- `IrBuilder#build` absence of synthetic endpoint FK attributes.
- Diagnostic schema/catalog fixtures.
- Rails matrix exact relationship projection.
- No private helper is asserted directly.

## TDD slices

1. Red: schema probe exposes no hidden join table. Green: public HABTM
   reflection inventory adds one normalized cached table.
2. Red: valid HABTM emits `ASSOCIATION_MACRO_OMITTED`. Green: one-sided default
   declaration emits one many-to-many edge without synthetic FK attributes.
3. Red: reciprocal/alias declarations duplicate or reorder the edge. Green:
   normalized signature and canonical winner emit one stable edge.
4. Red: custom scalar table/keys and self-HABTM collide or omit. Green: both
   use the same normalized signature with distinct columns.
5. Red: missing/invalid join shapes are generic or silent. Green: closed reason
   diagnostics cover unresolved, primary-key, missing, extra, and ambiguous
   table-global shapes and suppress every edge using that invalid table.
6. Red: one scoped/invalid alias suppresses a valid same-signature declaration.
   Green: the valid edge publishes and the declaration-local failure emits one
   warning.
7. Red: real Rails fixture expects a macro warning. Green: the exact HABTM edge
   replaces it on all three pairs and a mismatch regression fails the task.

## Planned changes

| Path | Purpose |
|---|---|
| `lib/rails_mmd/schema_probe.rb` | Domain join-table metadata cache |
| `lib/rails_mmd/relationship_builder.rb` | HABTM eligibility, identity, canonical edge, diagnostics |
| `schemas/diagnostics.schema.json` | Closed join-table invalid warning |
| `fixtures/schemas/diagnostics/**` | Valid and malformed diagnostic fixtures |
| `spec/rails_mmd/schema_probe_spec.rb` | Public hidden-table probing behavior |
| `spec/rails_mmd/relationship_builder_spec.rb` | Public HABTM edge/dedup/failure behavior |
| `spec/rails_mmd/ir_builder_spec.rb` | No synthetic endpoint FK projection |
| `spec/integration/rails_matrix_task_spec.rb` | Exact-oracle mismatch regression |
| `fixtures/rails_matrix/template/**` | Real reciprocal HABTM and exact expectations |
| `docs/p0-contract.md` | P1-07 eligibility, identity, cardinality, warning |
| `docs/active-record-association-support.md` | Mark P1-07 supported |

## Acceptance criteria

- Every eligible one-sided or reciprocal HABTM physical signature renders once.
- IDs, endpoints, labels, and both cardinalities are deterministic.
- The hidden join table is validated but never rendered as an entity and never
  contributes synthetic endpoint key attributes.
- Custom scalar table/key names and distinct-key self-HABTM work.
- Invalid/deferred declarations produce schema-valid warnings without blocking
  unrelated valid HABTM edges.
- Direct, through, and polymorphic output remains unchanged.
- Exact output, default Rake, pre-commit, and pre-push pass on all three matrix
  pairs.

## Design review record

| Round | Perspective | Findings | Correction |
|---|---|---|---|
| 1 | Rails runtime | None | — |
| 1 | Architecture | New join-table fields cannot extend the shared closed association metadata | Required a dedicated closed metadata shape |
| 1 | QA / TDD | Partial-success split and real reciprocal order proof were implicit | Split the TDD cases and made the exact order-invariance oracle explicit |
| 2 | Rails runtime | None | — |
| 2 | Architecture | None | — |
| 2 | QA / TDD | None | — |
