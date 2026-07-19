# P2-07 association behavior metadata implementation

Status: complete pending publication

## Delivered implementation slices

### Deep relationship metadata module

Added `RailsMmd::RelationshipMetadata` as the sole owner of behavior
normalization, advisory reflection reads, immutable internal fragments,
canonical merge, and the one-way internal-to-public projection.

| TDD slice | Red evidence | Green evidence |
|---|---|---|
| first dependent declaration | focused spec failed with `LoadError: cannot load such file -- rails_mmd/relationship_metadata` | 1 example, 0 failures |
| touch, counter cache, and failure containment | 5 examples produced 3 failures because touch/counter members were absent | 5 examples, 0 failures |
| scope, merge, dedup, ordering, and public projection | 7 examples produced 2 `NoMethodError` failures for missing `.scoped` | 7 examples, 0 failures |
| reflected string dependent enum | focused spec failed because the declaration normalized to `nil` | 8 examples, 0 failures |

The module reads `options` once under rescue containment and reads
`counter_cache_column` separately, so an unreadable derived counter column
cannot erase readable `dependent` or `touch` behavior. Exact duplicate records
are removed by canonical JSON identity and each direction is sorted by that
same identity before the deeply frozen result is returned.

### RelationshipBuilder integration

Every structurally eligible declaration is assigned a canonical direction
before deduplication. Existing relationship winner, identity, key, cardinality,
domain, and connection logic remains unchanged.

| TDD slice | Red evidence | Green evidence |
|---|---|---|
| reciprocal direct declarations | expected both directional arrays; actual metadata was `nil` | focused direct and existing scoped examples: 2 examples, 0 failures |
| effective through behavior | has-many/has-one through examples both returned `nil` metadata | focused through examples plus existing scope case: 3 examples, 0 failures |
| polymorphic root plus inverse | expected owner/target records; actual metadata was `nil` | focused polymorphic behavior and both existing ordering cases: 3 examples, 0 failures |
| delegated root/inverse/family scope | target-side inverse record was missing while root behavior survived | focused delegated cases: 3 examples, 0 failures |

HABTM continues to call the scoped-only entry point even when its raw reflection
echoes unsupported behavior options. Through behavior comes only from the outer
declaration. Polymorphic/delegated root and inverse fragments now use the same
merge instead of the former `candidate.metadata || root_metadata` overwrite.
Unreadable behavior options leave the edge and existing diagnostics intact.

The combined `RelationshipBuilder` and `RelationshipMetadata` suite passed:

```text
103 examples, 0 failures
```

### Public artifact schema and projection

IR and render plans moved atomically to schema version 5. The two schemas share
the same closed logical behavior shape with macro-specific declaration rules.
`IrBuilder` performs the only symbol-to-string projection;
`RenderPlanBuilder` copies present public IR metadata verbatim. Mermaid remains
unaware of behavior metadata.

| TDD slice | Red evidence | Green evidence |
|---|---|---|
| IR/render behavior projection | both focused examples exposed only `{scoped:true}` and rejected the expected behavior object | IR, render-plan, and schema contract group: 60 examples, 0 failures |
| durable v5 migration notice | README drift guard failed for missing v5 behavior and version-policy language | focused drift guard: 1 example, 0 failures |

All pre-existing IR/render/schema fixtures moved mechanically to v5, while new
stale-v4 fixtures prove the version cut. The contract suite also covers
behavior-only, scoped-plus-behavior, both directions, inactive counter cache,
empty/unknown shapes, duplicate records, invalid macros/actions/targets,
forbidden member combinations, and malformed touch/counter values.

The non-matrix unit and contract regression gate passed after these slices:

```text
376 examples, 0 failures
```

## Real matrix implementation

Added the `association_behavior` family to every declared matrix pair. Its
application declares reciprocal direct, through, polymorphic, delegated-type,
HABTM false-positive, inactive counter-cache, and inverse-only counter naming
cases. The family schema extends the shared matrix schema so the common STI
oracle can still load every application model before the domain-scoped P2-07
artifacts are generated.

The family runtime oracle records raw reflection declarations in a
version-independent normalized JSON shape. The separate checked-in pair probe
requires the exact locked Rails version and validates the upstream reflection
facts used by production normalization. Neither oracle calls production
`RelationshipMetadata` code.

The artifact gate exact-compares relationships, ER/class render plans,
Mermaid, diagnostics, polymorphic groups, STI projections, and both runtime
oracles. ER and class Mermaid remained behavior-free. The existing default
family relationship oracle was also advanced for its real `dependent:
:destroy` declaration.

Matrix task TDD first produced seven P2-07-path failures because the fake
runner did not execute the runtime/probe branches and exact render-plan checks
applied only to composite keys. After wiring those paths, the focused slice
passed `7 examples, 0 failures`. Missing, malformed, and mismatched runtime,
probe, relationship, and full-render-plan expectations were then added; the
focused expectation slice passed `5 examples, 0 failures`. Final QA exposed
two missing evidence seams: polymorphic identity drift was not rejected and a
supported has-one-through touch existed only in unit doubles. Both focused
examples failed before correction, then passed after the closed probe
projection and real family were extended. The real relationship oracle now
proves that has-many-through dependent behavior and has-one-through touch
survive together on the same canonical edge.

All three declared pairs produced the same checked-in public meaning:

```text
PASS ruby-4.0.6-rails-7.2 [association_behavior]
PASS ruby-3.3.12-rails-8.1 [association_behavior]
PASS ruby-4.0.6-rails-8.1 [association_behavior]
PASS 3/3 Rails matrix pairs
```

## Implementation review record

| Round | Specialist lens | Findings resolved | Result |
|---|---|---|---|
| 1 | Core architecture/correctness | Reviewed normalization boundary, canonical merge, artifact projection, and schema closure | 指摘なし |
| 1 | Rails semantics | Reviewed supported/ignored macro options, through ownership, polymorphic/delegated merge, and fail-soft reads | 指摘なし |
| 1 | QA/evidence | Closed polymorphic/delegated identity evidence and real has-one-through touch evidence were missing | corrected |
| 2 | QA/evidence | Re-reviewed the corrected probe, real family, expectations, and implementation record | 指摘なし |

## Final verification

Completed before repository hooks:

```text
RSpec:        450 examples, 0 failures
RuboCop:      170 files inspected, no offenses detected
Bundler Audit: No vulnerabilities found
Undercover:   No coverage is missing in latest changes
Rails matrix: all 6 fixture families passed on all 3 declared pairs
```

Pre-commit and pre-push are recorded after the final specialist review and
staging inspection.
