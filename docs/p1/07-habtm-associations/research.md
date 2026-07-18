# P1-07 HABTM Associations Research

Status: research complete and reviewed

## Target

Represent Rails 7.2/8.1 `has_and_belongs_to_many` declarations as one
deterministic many-to-many edge after validating their hidden join table.

## Rails facts

- Public HABTM reflections have macro `:has_and_belongs_to_many` and are not
  returned by the `:has_many` macro filter.
- Rails implements HABTM with a hidden join model and synthetic `has_many`
  machinery. Only public reflections may be inventoried; private reflection
  storage can double-count the relationship.
- Reflection methods expose `klass`, `join_table`, `foreign_key`, and
  `association_foreign_key`. `klass` and a default-derived `join_table` may
  raise until the target class resolves, so both require safe reads and the
  unresolved-target omission path. After resolution these values cover default
  and custom scalar names, `class_name`, and self-HABTM.
- The default join-table name is derived from the two model table names in
  lexical order with a shared prefix collapsed. Reading the resolved reflection
  value is safer than reproducing that algorithm.
- A conventional HABTM join table has no primary key. Rails recommends
  `id: false`; extra join attributes are deprecated/read-only and indicate that
  `has_many :through` is the richer abstraction.
- Reciprocal HABTM declarations cannot rely on normal automatic inverse
  detection. They must be merged by join table, endpoint entities, and join
  columns.
- HABTM is a collection on both ends. Its conservative ER cardinality is
  `0..many` to `0..many`; indexes and database FKs do not make either endpoint
  singular.
- Rails 8.1 adds the association option `deprecated`; the structural reflection
  surface used here is otherwise unchanged from Rails 7.2.

## Repository facts

- P1-02 currently classifies HABTM as `ASSOCIATION_MACRO_OMITTED`.
- Direct, through, and polymorphic relationships already occupy separate
  internal identity spaces. HABTM needs a fourth physical signature.
- Public relationship/render-plan schemas already represent a labeled edge
  with endpoint cardinalities; no schema expansion is required.
- Join-table columns belong to a hidden table, not either rendered entity.
  `IrBuilder` must not mark them as owner/target FK attributes.
- `SchemaProbe` owns database inspection, but currently probes selected model
  tables only. `RelationshipBuilder` must not gain raw connection access.
- `SchemaProbe::DomainResult` is a keyword-initialized struct and can carry an
  optional domain-level join-table cache without breaking existing callers.

## Minimum safe scope

- Inventory only public `:has_and_belongs_to_many` reflections.
- Require an unscoped, safely named declaration and a renderable selected
  same-domain target.
- Accept scalar resolved `join_table`, `foreign_key`, and
  `association_foreign_key` values, including custom names and `class_name`.
- Require both selected entities to have scalar actual primary keys; custom or
  composite primary-key behavior remains deferred.
- Require readable join-table metadata, no join-table primary key, two distinct
  join columns, and exactly those two columns. A custom join table with
  timestamps or any other payload column is always invalid in P1-07 and remains
  deferred to `has_many :through`.
- A one-sided declaration is sufficient because Rails supports it. A matching
  reciprocal or alias declaration is deduplicated silently.
- Support self-HABTM only when the two scalar join columns are distinct.
- Indexes and database FK constraints are evidence but are not eligibility
  requirements in P1-07.

## Identity and projection boundaries

- Normalize two endpoint tuples `(entity_id, join_column)` lexically.
- Internal physical key:
  `habtm|<join_table>|<left_entity>|<left_column>|<right_entity>|<right_column>`.
- Recommended public ID:
  `relationships/<left_table>/habtm/<join_table>/<left_column>/<right_table>/<right_column>`.
- The join table and both columns are public identity dimensions so reciprocal,
  alias, custom-key, and self relationships cannot collide accidentally.
- Public orientation starts at the normalized left endpoint, matching existing
  relationship ID families. The canonical label is the lexical declaration
  winner, independent of reflection enumeration order.
- Join-table columns are not projected into entity attributes.

## Failure boundaries

- Reuse existing target, domain, scope, unsafe-name, and primary-key omission
  diagnostics.
- Add one schema-closed `ASSOCIATION_JOIN_TABLE_INVALID` warning for join-table
  shape failures. Its metadata should add sanitized `join_table` and a closed
  reason enum to the common association identity.
- Candidate reasons: unresolved table, primary key present, missing join
  column, extra column, or ambiguous equal join columns.
- Declaration-local failures are partial: a valid declaration still publishes
  when a scoped or otherwise invalid reciprocal/alias declaration names the
  same physical signature, and the invalid declaration gets one warning.
  Join-table-global shape failures invalidate every declaration using that
  table. A reverse/alias declaration with a different physical signature is
  independently diagnosed rather than merged.

## Required test boundaries

- One-sided default HABTM happy path.
- Reciprocal and same-side alias deduplication with reverse enumeration order.
- Custom join table/columns and `class_name`.
- Self-HABTM with distinct keys.
- Missing table, missing column, primary key, extra column, equal-key, scope,
  unresolved/non-renderable/out-of-domain target, and non-primary/composite
  endpoint keys.
- No synthetic join-table FK attributes in public entity IR.
- Real reciprocal fixture and exact relationship oracle on all three supported
  Rails/Ruby pairs. The oracle compares relationship ID, owner/target safe
  tokens, label, and both endpoint cardinalities so duplicate suppression and
  canonical orientation are exact.
- Task-level mismatch regression proving the exact HABTM oracle is enforced.

## Research review record

| Round | Perspective | Findings | Correction |
|---|---|---|---|
| 1 | Rails runtime | `klass` and default `join_table` can raise before target resolution | Required safe reads and the unresolved-target path |
| 1 | Architecture | Kind-first public ID diverged from every existing relationship family | Moved normalized left table before `habtm` |
| 1 | QA / TDD | Extra-column policy, exact oracle fields, and partial-success grouping were implicit | Closed all three acceptance boundaries |
| 2 | Rails runtime | None | — |
| 2 | Architecture | None | — |
| 2 | QA / TDD | None | — |

## Sources

- [Rails 7.2 Association Class Methods](https://api.rubyonrails.org/v7.2/classes/ActiveRecord/Associations/ClassMethods.html)
- [Rails 8.1 Association Class Methods](https://api.rubyonrails.org/v8.1/classes/ActiveRecord/Associations/ClassMethods.html)
- [Rails Association Basics](https://guides.rubyonrails.org/association_basics.html)
- [Rails 7.2 reflection source](https://github.com/rails/rails/blob/7-2-stable/activerecord/lib/active_record/reflection.rb)
- [Rails 8.1 reflection source](https://github.com/rails/rails/blob/8-1-stable/activerecord/lib/active_record/reflection.rb)
