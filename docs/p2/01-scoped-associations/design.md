# P2-01 Scoped Associations Design

## Decisions

### Public metadata contract

- Add optional `metadata` to IR and render-plan relationship objects.
- The only P2-01 value is `{ "scoped": true }`.
- The metadata object is closed, requires `scoped`, and constrains it with
  `const: true`. `null`, `{}`, `false`, and extra members are invalid.
- Unscoped relationships omit `metadata`; they never publish
  `{ "scoped": false }`.
- Mermaid output does not change. The metadata is machine-readable artifact
  data, not an edge-label suffix.
- Bump IR and render-plan `schema_version` from 1 to 2. Both v1 relationship
  objects are closed, so a new optional member still expands the accepted
  instance set and old strict consumers would reject scoped v1 artifacts.
  Diagnostics and configuration schemas remain at version 1 because their
  shapes do not change. P2-01 does not add dual-version output negotiation;
  a durable `README.md` schema migration section must tell clients that IR and
  render plans now require the v2 schemas, while diagnostics/config stay v1.

Define the same closed `relationship_metadata` shape in both public schemas and
reference it from the relationship definition. `IrBuilder` converts the internal
symbol-keyed value to JSON keys. `RenderPlanBuilder` copies only the normalized
member; it does not accept arbitrary relationship metadata.

### Internal record and safe scope observation

- Extend `RelationshipBuilder::Relationship` with `metadata`.
- Internal values are `nil` or the frozen-value equivalent of
  `{ scoped: true }`.
- For direct and HABTM declarations, use `reflection.scope` presence after the
  existing reflection classification; never invoke the proc.
- Remove scope-only omission gates while keeping name, target, renderability,
  domain, key, join-table, and polymorphic eligibility gates in their current
  order.
- `ASSOCIATION_SCOPED_OMITTED` remains schema-valid for old artifacts but is no
  longer emitted for otherwise supported scoped relationships.

### Through associations

- Preserve current resolution order and failure diagnostics for outer options,
  through reflection, source reflection, lineage, and join chain.
- Do not use `ThroughReflection#has_scope?`: it includes `source_type`.
- After safe chain resolution succeeds, compute scope presence by boolean OR of
  actual `scope` proc presence on the outer declaration and resolved source,
  through, lineage, and chain reflections.
- Explicit `source:` stays `ASSOCIATION_MACRO_OMITTED`. `source_type:` and
  polymorphic hops stay `ASSOCIATION_POLYMORPHIC_OMITTED`. Only after these
  structural gates and safe resolution pass may P2-01 observe actual scope-proc
  presence. Unresolved chains keep their current omission paths.

### Polymorphic associations

- A supported polymorphic root or matching inverse scope no longer causes a
  scoped omission.
- Preserve the two-pass inventory and never call `klass` on a polymorphic
  `belongs_to`.
- Each concrete candidate edge is scoped when the root or any matching inverse
  declaration contributing to that candidate is scoped.
- An unmatched or deferred inverse `as:` declaration emits
  `ASSOCIATION_POLYMORPHIC_OMITTED` even when scoped. Scope no longer outranks
  the missing-root structural failure, and it does not invent a candidate.

### Canonical deduplication

- Winner selection for identity, label, endpoints, and cardinality remains
  unchanged.
- After selecting a canonical winner, merge candidate metadata with boolean OR.
- Apply the merge to every canonical group: direct physical keys, HABTM physical
  keys, through semantic keys, and polymorphic candidate groups.
- Enumeration order cannot change the result.

### Matrix oracle and documentation

- Extend `tooling/rails_matrix.rb#relationship_projection` with optional
  `metadata`. Omission remains observable because the key is absent for unscoped
  relationships.
- Add a real scoped declaration whose proc raises if executed and an exact
  expected relationship on every declared matrix pair.
- Add a task-level regression proving a changed scoped metadata expectation
  fails the matrix validator.
- Mark P2-01 supported in `docs/active-record-association-support.md` and add the
  v2 client migration contract to `README.md`. Do not rewrite
  `docs/p0-contract.md`: it remains the P0 baseline contract and may continue to
  describe P0's scoped-association omission.

## Public TDD seams

The user approved all test seams for this run. P2-01 uses only these public
boundaries:

- `RelationshipBuilder#build` relationships and diagnostics.
- `IrBuilder#build` public IR payload and schema validation.
- `RenderPlanBuilder#build` ER/class artifact payload and schema validation.
- `RailsMmd::SchemaValidator` through checked-in valid/invalid fixtures.
- `Rake::Task['verify:rails_matrix']` through the shared real application and
  exact oracle.

Tests do not call private helpers, evaluate a scope, or assert proc internals.
Expected metadata values are checked-in literals, not recomputed by production
logic.

## Vertical TDD slices

Each slice is one failing public-seam example followed by the minimum code to
make it pass. Refactoring waits for implementation review.

1. Direct scoped `belongs_to` produces one relationship with internal
   `{ scoped: true }` and no scoped-omission diagnostic.
2. Direct scoped `has_many` and `has_one` preserve metadata on the target-FK
   path without changing cardinality.
3. Scoped HABTM passes existing join-table validation and publishes metadata.
4. Mixed scoped/unscoped equivalent direct declarations collapse to one scoped
   relationship in both enumeration orders.
5. Mixed scoped/unscoped HABTM aliases collapse to one scoped relationship in
   both enumeration orders.
6. One outer scoped through declaration publishes metadata after safe chain
   resolution.
7. One scoped source hop publishes through metadata without executing its proc.
8. One scoped through hop publishes through metadata without executing its proc.
9. Explicit `source:` remains `ASSOCIATION_MACRO_OMITTED` and does not publish
   scope metadata.
10. `source_type` remains `ASSOCIATION_POLYMORPHIC_OMITTED` and does not publish
   scope metadata.
11. Mixed scoped/unscoped same-path through declarations retain scoped metadata
    in both enumeration orders.
12. A scoped polymorphic root publishes metadata on each resolved candidate.
13. A scoped polymorphic inverse publishes candidate-local metadata.
14. A scoped rootless inverse remains `ASSOCIATION_POLYMORPHIC_OMITTED`.
15. Mixed scoped/unscoped same-target polymorphic candidates retain scoped
    metadata in both enumeration orders.
16. IR schema version 2 projects optional metadata and accepts the closed valid
    value.
17. IR rejects `null`, empty, false, wrong-type, and extra-key metadata cases.
18. The ER render plan preserves optional metadata under schema version 2.
19. The class render plan preserves optional metadata under schema version 2.
20. Render-plan schema fixtures reject each invalid metadata shape.
21. The matrix exact projection observes a raising scoped proc without executing
    it on all three pairs.
22. A task-level changed expectation fails with the exact relationship mismatch.

For every regression test, record red evidence before production changes and
green evidence after the minimum change. When practical, also prove sensitivity
by reverting the production hunk after green, observing red, and restoring it.

## Planned files

- `lib/rails_mmd/relationship_builder.rb`
- `lib/rails_mmd/ir_builder.rb`
- `lib/rails_mmd/render_plan_builder.rb`
- `schemas/ir.schema.json`
- `schemas/render_plan.schema.json`
- `spec/rails_mmd/relationship_builder_spec.rb`
- `spec/rails_mmd/ir_builder_spec.rb`
- `spec/rails_mmd/render_plan_builder_spec.rb`
- `spec/contracts/schema_spec.rb`
- `spec/integration/rails_matrix_task_spec.rb`
- relevant valid/invalid schema fixtures
- real Rails fixture models and `rails_mmd_expected_relationships.json`
- `tooling/rails_matrix.rb`
- `docs/active-record-association-support.md`
- `README.md`
- `docs/p2/01-scoped-associations/implementation.md`

## Acceptance criteria

- Otherwise valid scoped direct, through, HABTM, and polymorphic relationships
  are represented once with `metadata.scoped: true`.
- IR and render-plan artifacts publish schema version 2. Apart from that top-level
  migration, unscoped relationship payloads remain byte-for-byte unchanged.
- Scope procs never execute during discovery, normalization, or rendering.
- `source_type` and unresolved/unsupported structural cases keep their assigned
  omission behavior.
- Canonical metadata merging is deterministic for every relationship kind.
- IR/render-plan schemas accept only the closed scoped metadata value.
- Exact matrix output and mismatch sensitivity pass on every declared pair.
- Targeted specs, default Rake, pre-commit, and pre-push pass.

## Design contribution record

| Perspective | Contribution | Disposition |
|---|---|---|
| Rails runtime | Safe per-hop proc-presence algorithm and canonical merge seams | Accepted |
| Public API/schema | Exact closed metadata schema and strict-consumer compatibility risk | Accepted; IR/render-plan schema version bumped to 2 |
| Test automation | Suggested diagnostic-only metadata and continued omission | Rejected because it contradicts the reviewed P2-01 success contract; its matrix-sensitivity concern was retained |

## Design review record

| Round | Perspective | Findings | Correction |
|---|---|---|---|
| 1 | Rails runtime | Exact preserved through diagnostics and scoped rootless inverse replacement were implicit | Named `source:`/`source_type:` codes and made rootless scoped inverses polymorphic omissions |
| 1 | Architecture/API | Adding metadata to closed v1 relationship objects breaks strict v1 consumers | Bumped IR and render-plan schema versions to 2; other schemas stay at 1 |
| 1 | QA / TDD | Through/polymorphic dedup cases were missing and several slices combined branches | Added both-order dedup cases and split every independent positive/negative branch |
| 2 | Rails runtime | None | — |
| 2 | Architecture/API | P2 behavior was planned as a rewrite of the P0-only baseline contract | Kept P0 contract unchanged and moved v2 migration ownership to P2/user docs |
| 2 | QA / TDD | Explicit `source:` preservation lacked its own public-seam slice | Added an independent `ASSOCIATION_MACRO_OMITTED` slice |
| 3 | Architecture/API | Migration guidance lacked a named durable user-facing owner | Required a `README.md` schema migration section |
| 3 | QA / TDD | None | — |
| 4 | Architecture/API | Named migration owner existed only in the design plan | Added the durable schema-version migration section to `README.md` |
| 5 | Architecture/API | None | — |
