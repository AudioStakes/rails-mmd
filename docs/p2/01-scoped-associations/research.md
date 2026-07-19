# P2-01 Scoped Associations Research

## Target

Represent supported scoped associations instead of omitting them, and retain
scope presence as relationship metadata without executing the scope.

P2-01 owns association scope presence only. It does not own `source_type`,
custom-key resolution, lifecycle options, default-scope introspection, scope
source locations, SQL generation, or scope-proc serialization.

## Rails facts

- Rails 7.2.3.1 and 8.1.3 accept an optional scope for `belongs_to`, `has_one`,
  `has_many`, and `has_and_belongs_to_many`.
- `MacroReflection#scope` exposes the stored proc. Reading it observes presence;
  `scope_for` is the separate execution boundary that invokes the proc with
  `instance_exec`.
- For non-through reflections, `has_scope?` is equivalent to declaration scope
  presence. `ThroughReflection#has_scope?` is broader: it also becomes true for
  `source_type`, even without a scope proc. P2-01 must therefore inspect actual
  declaration/source/through-hop proc presence only after safe chain resolution;
  it must not classify `source_type` as scope metadata.
- A target model's `default_scope` participates later in association query
  construction. It is not declaration-local association scope metadata.
- No P2-01-relevant behavior difference was found between the supported Rails
  7.2 and 8.1 lines.

Therefore rails-mmd may read scope presence from already inventoried or already
resolved reflections, but must never call `scope_for`, `join_scopes`, or the
scope proc itself.

## Repository facts

- `RelationshipBuilder` currently turns scoped declarations into
  `ASSOCIATION_SCOPED_OMITTED` at separate direct, HABTM, through, and
  polymorphic paths.
- Through omission precedence also detects scoped source and through hops.
- The internal `Relationship` record and the IR/render-plan relationship schemas
  have structural fields but no association metadata channel.
- `IrBuilder` is the stable boundary that projects normalized relationship
  records into public IR; `RenderPlanBuilder` carries the public subset into both
  diagram kinds.
- The matrix oracle currently compares relationship identity, endpoints, label,
  and cardinalities. It does not prove optional relationship metadata.
- Diagnostic metadata is the wrong persistence location: scoped declarations
  should no longer be omissions, and diagnostic metadata is not present on a
  successful relationship.

## Alternatives

### A. Keep the omission and add diagnostic metadata

Rejected. This records why an association disappeared, not scope presence on a
represented relationship, and fails the supported-behavior intent.

### B. Add one top-level boolean to every relationship schema

Viable but weakly extensible. It makes future association annotations compete
for top-level relationship fields and cannot distinguish where a through scope
was observed.

### C. Add closed optional relationship metadata

Selected. A closed optional `metadata` object carries only `scoped: true` when
an association scope exists. P2-01 adds no future-option placeholders and does
not publish scope origins, proc content, source locations, or SQL.

For every canonical relationship deduplication group, metadata merging is
boolean OR: if any retained declaration is scoped, the canonical relationship
publishes `metadata.scoped: true`, independent of reflection order. This covers
direct physical edges, same-path through edges, HABTM reciprocal or alias
collapse, and polymorphic candidate collapse. Origin detail, if ever useful
internally, is non-public and cannot affect relationship identity,
deduplication, or public artifact bytes.

## Risks and required boundaries

- A raising or side-effecting scope proc must remain uncalled.
- Reciprocal or aliased reflections can collapse to one physical relationship;
  a scoped and an unscoped equivalent declaration must yield one edge whose
  `metadata.scoped` remains `true` in either enumeration order.
- Through metadata must not turn P2-05 `source_type` into P2-01 scope support.
- Polymorphic candidate expansion must retain scope presence without calling
  `klass` on a polymorphic `belongs_to`.
- HABTM join-table validation remains authoritative; adding metadata must not
  bypass its schema checks.
- Existing unscoped public output should remain byte-for-byte stable if the
  optional metadata member is absent.
- The real Rails matrix must assert metadata on all declared pairs, not merely
  prove that a scoped declaration boots.

## Required public test boundaries

- `RelationshipBuilder#build`: direct scoped `belongs_to`, `has_one`, and
  `has_many`; scoped HABTM; through declaration/source/through-hop scope;
  polymorphic root/candidate scope; unresolved chains; and order-independent
  deduplication.
- `IrBuilder#build`: normalized metadata appears on successful relationships and
  unscoped relationships omit it.
- `RenderPlanBuilder#build`: both artifact plans preserve the schema-valid
  metadata member.
- Schema contracts: valid scoped metadata, invalid extra keys/types, and
  unchanged closed-object behavior.
- Shared real app: a scoped declaration whose proc would fail if executed, plus
  exact `metadata` projection on every Rails/Ruby matrix pair. Extend
  `tooling/rails_matrix.rb` relationship projection and the checked-in expected
  relationships fixture so this is compared directly.
- Task-level oracle regression: changing the scoped expectation must make the
  matrix validator fail.

No test may assert a private helper or inspect proc implementation details.

## Research review record

| Round | Perspective | Findings | Correction |
|---|---|---|---|
| 1 | Rails runtime | Through `has_scope?` also treats `source_type` as scoped | Required per-hop proc-presence inspection after safe chain resolution and kept `source_type` in P2-05 |
| 1 | Architecture | Public origin detail required new order-sensitive merge semantics and expanded P2-01 | Fixed the public shape to optional `{ scoped: true }` and boolean-OR deduplication |
| 1 | QA / TDD | Metadata shape, exact matrix seam, and scoped/unscoped dedup oracle were not executable | Fixed the shape and named the validator, fixture, and mixed-declaration expectation |
| 2 | Rails runtime | None | — |
| 2 | Architecture | Boolean-OR was not explicit for duplicate through semantic paths | Applied the same merge rule to physical and same-path through deduplication |
| 2 | QA / TDD | None | — |
| 3 | Rails runtime | None | — |
| 3 | Architecture | Merge rule named only direct/through groups, not HABTM/polymorphic canonical groups | Applied boolean OR to every canonical relationship deduplication group |
| 3 | QA / TDD | None | — |
| 4 | Architecture | None | — |

## Sources

- [Rails 7.2.3.1 association declarations](https://github.com/rails/rails/blob/v7.2.3.1/activerecord/lib/active_record/associations.rb)
- [Rails 7.2.3.1 reflection implementation](https://github.com/rails/rails/blob/v7.2.3.1/activerecord/lib/active_record/reflection.rb)
- [Rails 8.1.3 association declarations](https://github.com/rails/rails/blob/v8.1.3/activerecord/lib/active_record/associations.rb)
- [Rails 8.1.3 reflection implementation](https://github.com/rails/rails/blob/v8.1.3/activerecord/lib/active_record/reflection.rb)
- `docs/active-record-association-support.md`
- `docs/p1/02-association-detection/design.md`
- `docs/p1/05-through-associations/research.md`
- `lib/rails_mmd/relationship_builder.rb`
- `lib/rails_mmd/ir_builder.rb`
- `lib/rails_mmd/render_plan_builder.rb`
- `schemas/ir.schema.json`
- `schemas/render_plan.schema.json`
- `tooling/rails_matrix.rb`
