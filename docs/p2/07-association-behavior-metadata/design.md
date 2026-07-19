# P2-07 association behavior metadata design

Status: complete

## Goals

- Publish normalized `dependent`, `touch`, and `counter_cache` semantics on
  relationships that already survive structural selection.
- Preserve which canonical endpoint owns each lifecycle declaration after
  reciprocal, alias, polymorphic, and delegated-type collapse.
- Keep extraction advisory and non-executing: unreadable behavior never removes
  an otherwise valid edge.
- Keep metadata deterministic, lossless for conflicting declarations, and
  identical in IR and render plans.
- Advance IR and render-plan artifacts atomically from schema version 4 to 5;
  keep Mermaid, diagnostics, and configuration contracts unchanged.

## Non-goals

- Executing callbacks, scopes, persistence methods, or association readers.
- Inferring callbacks that Rails does not declare on a supported reflection.
- Publishing arbitrary reflection options or HABTM option echoes.
- Decorating Mermaid relationship labels.
- Changing relationship identity, cardinality, domain/connection gates, key
  resolution, safe-token assignment, or diagnostic precedence.
- Providing v4 output negotiation or a dual-version compatibility mode.

## Module boundary

Add `RailsMmd::RelationshipMetadata` in
`lib/rails_mmd/relationship_metadata.rb`. It is the single deep module that owns
safe behavior extraction, internal metadata construction, deterministic merge,
and public JSON projection. `RelationshipBuilder` owns only the structural
question of which reflection contributes to which canonical direction.
`SchemaProbe` remains unaware of behavior options.

The public Ruby methods are:

```ruby
RelationshipMetadata.for_declaration(
  reflection:,
  association_name:,
  association_macro:,
  through:,
  direction:,
  scoped:
) # deeply frozen symbol-keyed metadata or nil

RelationshipMetadata.scoped(scoped) # { scoped: true } or nil
RelationshipMetadata.merge(*metadata_values) # normalized/frozen metadata or nil
RelationshipMetadata.public_payload(metadata) # closed string-keyed JSON hash or nil
```

`for_declaration` accepts builder-established macro, sanitized name, through
classification, and direction instead of rediscovering structural facts. Its
only reflection reads are `options` and, for a supported `belongs_to` counter,
`counter_cache_column`. Each read is individually contained with
`LoadError`, `SyntaxError`, and `StandardError`; a failed counter-column read
does not discard a readable `dependent` or `touch` value. The method never
calls `klass`, an association accessor, a scope proc, a callback, or persistence
code. Reflection readers can themselves be monkey-patched application code, so
they are treated as contained untrusted reads rather than claimed to be inert.
An unreadable `options` hash omits every option from that declaration but never
the edge. A polymorphic inverse name that does not pass the public association
name sanitizer similarly contributes no behavior record while leaving the
root-owned structural edge eligible.

`public_payload` is a one-way projection that explicitly reconstructs the
closed contract from internal symbol-key metadata. `IrBuilder` is its only
caller. `RenderPlanBuilder` copies present metadata from schema-valid public IR
without normalizing or interpreting it again; the render-plan schema rejects a
malformed input shape. This keeps render planning a deterministic projection,
not a second semantic implementation.

## Internal metadata invariant

Internal metadata has the same hierarchy as public metadata but uses symbols:

```ruby
{
  scoped: true,
  behavior: {
    from_owner: [declaration, ...],
    from_target: [declaration, ...]
  }
}
```

Every optional empty member is removed. The complete result is `nil` when both
scope and behavior are absent. Every retained array and hash is copied and
deeply frozen before it is stored on `Relationship`.

`RelationshipMetadata.merge` performs these operations:

1. compact absent inputs;
2. retain `scoped: true` when any input is scoped;
3. concatenate declaration records separately for `from_owner` and
   `from_target`;
4. compute `CanonicalJson.dump(record)` once per record;
5. remove only records with identical canonical JSON;
6. sort the surviving records by canonical JSON;
7. omit empty directions, omit empty `behavior`, and return `nil` if empty.

Different records with the same association name remain distinct. Winner
selection for label, identity, macro, and cardinality never chooses behavior.
This merge replaces `RelationshipBuilder#merged_relationship_metadata` for all
direct, through, polymorphic, and HABTM canonical groups.

## Declaration normalization

Every declaration record requires:

```json
{
  "association_name": "account",
  "association_macro": "belongs_to"
}
```

and at least one behavior member. The extractor applies a closed allowlist:

| Macro | Through | Published members |
|---|---:|---|
| `belongs_to` | no | supported `dependent`, `touch`, `counter_cache` |
| `has_one` | no | supported `dependent`, `touch` |
| `has_one` | yes | supported `touch`; ignore `dependent` |
| `has_many` | no | supported `dependent` |
| `has_many` | yes | supported `dependent` targeting through records |
| HABTM | either | none; builder requests scoped-only metadata |

`dependent` becomes:

```json
{ "action": "destroy", "target": "associated_records" }
```

Allowed actions are macro-specific Rails enums. `has_many :through` is the only
shape using `"target": "through_records"`; every other published dependent
uses `associated_records`. Unsupported, missing, or non-symbol/string action
values are omitted.

`touch: true` becomes `{ "attribute": null }`. A named symbol/string becomes a
string only when it matches the structured column-name pattern. Other values
are omitted. Touch is published only for `belongs_to` and `has_one`.

Counter cache is published only for `belongs_to`. The normalized Rails option
must be a hash whose `active` value is exactly boolean. The derived
`counter_cache_column` must be a structured column name. The public value is:

```json
{ "column": "members_count", "active": true }
```

An inactive cache is retained. Raw `has_many` inverse naming and HABTM option
echoes are deliberately ignored even when Rails' generic reflection readers
report them as cached counters.

## Canonical direction mapping

`from_owner` and `from_target` refer to the final public relationship endpoints.
The builder supplies direction only after structural eligibility succeeds:

| Relationship source | Declaration owner after canonicalization | Direction |
|---|---|---|
| direct `belongs_to` | foreign-key holder, canonical owner | `from_owner` |
| direct `has_one` / `has_many` | referenced entity, canonical target | `from_target` |
| outer `has_one` / `has_many :through` | semantic canonical owner | `from_owner` |
| polymorphic/delegated root `belongs_to` | foreign-key holder, canonical owner | `from_owner` |
| matching polymorphic/delegated inverse | concrete target, canonical target | `from_target` |
| HABTM | no P2-07 behavior | none |

Through metadata comes only from the outer declaration. Source/through/lineage
reflections still contribute to P2-01 scope detection, but their behavior
belongs to their own declarations and is not copied to the semantic through
edge.

For a polymorphic root, build root metadata once and merge it into each
surviving concrete candidate. Canonical inverse candidates merge every valid
inverse reflection for that concrete target before winner selection. Delegated
targets use the same root/inverse merge; delegated-family scope remains a
scoped-only contribution. Domain, connection, target, and key failures occur
before this merge, so omitted candidates cannot leak metadata.

## Public schema version 5

Both `schemas/ir.schema.json` and `schemas/render_plan.schema.json` change their
top-level `schema_version` constant to 5 and share this logical closed shape:

```text
relationship_metadata
  additionalProperties: false
  properties: scoped, behavior
  anyOf: required scoped | required behavior

behavior
  additionalProperties: false
  properties: from_owner, from_target
  anyOf: required from_owner | required from_target
  each direction: array, minItems 1, uniqueItems true

declaration
  oneOf: belongs_to shape | has_one shape | has_many shape
  association_name + association_macro + at least one behavior member
```

The macro-specific `oneOf` branches enforce allowed members, dependent actions,
and the semantic targets that can exist for each macro. The public declaration
does not expose whether its source reflection was `through`, so the schema does
not claim to distinguish direct `has_many` from `has_many :through` or direct
`has_one` from `has_one :through`. Builder tests own those source-specific rules,
including direct-has-many rejection of `through_records` and omission of
has-one-through dependent. `touch.attribute` is either `null` or a structured
column string. `counter_cache.column` is a structured column string and
`active` is boolean. Every nested object is closed; empty metadata, behavior,
direction arrays, and declaration records are invalid.

Valid fixtures cover scoped-only, behavior-only, mixed, both directions,
inactive counter cache, every macro, and through-record dependent behavior.
Invalid fixtures cover stale-v4 IR and render-plan documents, unknown keys at every level, empty shapes, invalid
macros/actions/targets, forbidden macro/member combinations, malformed names
and columns, non-boolean active state, duplicate array items, and missing
required declaration behavior.

README's `Artifact Schema Versions` section records that IR and render plans
move together to v5, v4 output is unavailable, consumers must use same-release
schemas, and diagnostics/configuration remain v1. The existing contract drift
guard asserts the durable v5 migration phrases so a later README rewrite cannot
silently remove the client requirement.

## Builder and renderer changes

- Replace each ad hoc `{ scoped: true }` construction with
  `RelationshipMetadata.for_declaration` or `.scoped`.
- Direct and through candidates receive metadata only after their current
  structural checks pass.
- Polymorphic inverse candidate canonicalization uses
  `RelationshipMetadata.merge` instead of overwriting metadata with scope.
- Polymorphic root/candidate and delegated root/inverse/family contributions
  use the same merge operation.
- Every canonical relationship group calls `RelationshipMetadata.merge` over
  candidate metadata.
- `IrBuilder` sets schema version 5 and attaches the result of
  `RelationshipMetadata.public_payload` only when non-nil.
- `RenderPlanBuilder` sets schema version 5 and copies present metadata from
  validated IR verbatim; it neither calls `public_payload` nor re-derives it.
- Mermaid serializers remain unchanged and continue to ignore relationship
  metadata.

## TDD public seams

Implementation uses `$tdd`. Tests exercise only public methods and public
builder/artifact boundaries; no spec sends private helper methods.

- `RelationshipMetadata.for_declaration`, `.merge`, and `.public_payload` for
  normalization, safe-reader containment, deep immutability, and deterministic
  ordering.
- `RelationshipBuilder#build` for structural gating, canonical direction, and
  reciprocal/alias/polymorphic/delegated merge behavior.
- `IrBuilder#build` and `RenderPlanBuilder#build` for exact v5 projection and
  behavior-free omission.
- `SchemaValidator` through checked-in valid/invalid fixtures.
- `Rake::Task['verify:rails_matrix']` through a real Rails application, runtime
  oracle, exact relationship/full-render-plan/Mermaid fixtures, and negative
  task paths.

Expected values are checked-in literals, never recomputed with production
normalizers.

## Vertical red-green-refactor slices

Record a focused failing example before each production slice, make only that
slice green, then refactor while it stays green.

1. `RelationshipMetadata` publishes direct `belongs_to dependent` in
   `from_owner` and deeply freezes the result.
2. Add named/default touch normalization and invalid-value omission.
3. Add active/inactive/default/custom belongs-to counter normalization, with a
   raising column reader omitting only counter data.
4. Add macro-specific dependent allowlists, has-one-through dependent
   exclusion, and has-many-through `through_records` targeting.
5. Add scoped-only, mixed scoped/behavior, and completely empty omission.
6. Add exact dedup and canonical-JSON ordering for multiple records in each
   direction, including conflicting same-name records and both input orders.
7. Direct `belongs_to` builder output maps behavior to `from_owner` without
   changing identity/cardinality.
8. Reciprocal direct `has_one` / `has_many` behavior maps to `from_target` and
   merges with the belongs-to candidate in both reflection orders.
9. Direct alias declarations preserve distinct records and remove exact
   duplicates.
10. Outer `has_many :through dependent` publishes `through_records`; outer
    `has_one :through dependent` stays absent while valid touch remains.
11. HABTM raw behavior options remain absent while scoped metadata survives.
12. Polymorphic root behavior is copied to each valid target and inverse
    behavior is candidate-local; rootless/omitted candidates publish nothing.
13. Delegated root and every valid inverse merge without losing delegated-family
    scope; rejected delegated targets publish nothing.
14. Cross-domain and cross-connection omissions retain current diagnostics and
    expose no behavior metadata.
15. IR moves to v5 and projects exact scoped-only, behavior-only, mixed, and
    both-direction metadata; behavior-free relationship bytes stay unchanged.
16. ER/class render plans move to v5 and preserve exact IR metadata; safe tokens,
    labels, markers, multiplicities, and Mermaid remain unchanged.
17. v5 schema valid fixtures pass; explicit stale-v4 IR/render-plan fixtures and
    every closed-shape invalid fixture fail in both schemas.
18. The dedicated real `association_behavior` family passes its runtime oracle,
    exact relationships, exact ER/class render plans, and unchanged Mermaid on
    all three declared Ruby/Rails pairs.
19. Matrix task specs reject missing, malformed, and mismatched runtime evidence.
20. Matrix task specs reject missing, malformed, and mismatched relationship and
    full render-plan expectations.
21. Pair-probe task specs reject malformed output and semantically mismatched
    pinned reflection evidence.

After each green slice, run the focused spec. After module/builder/schema/matrix
milestones, run the affected spec directories. Final evidence is the complete
RSpec suite, RuboCop, dependency audit, Undercover, all matrix families on all
three pairs, and both repository hooks.

## Real matrix family

Add `association_behavior` to `fixtures/rails_matrix/matrix.yml` and create a
self-contained family under
`fixtures/rails_matrix/template/families/association_behavior`.

The real app declares:

- reciprocal direct belongs-to/has-many dependent behavior;
- named touch and active/inactive counter caches;
- direct has-one behavior;
- has-many-through dependent and ignored has-one-through dependent;
- polymorphic root/inverse behavior;
- delegated root/inverse behavior;
- an HABTM unsupported-option echo that must not publish behavior;
- one structurally omitted candidate proving no metadata leak.

Its runtime oracle records Rails reflection options and derived counter readers
without using production normalization. The artifact oracle adds optional
metadata to the existing exact relationship projection and exact-compares both
ER/class render-plan JSON documents for this family. Checked-in Mermaid remains
behavior-free. `FAMILY_RUNTIME_ORACLES` owns runtime wiring; no one-off command
path is introduced.

Also register the committed research probe in `PAIR_PROBES` and validate it
with a dedicated validator. The validator first requires the exact locked Rails
version for the selected pair, then validates the remaining closed reflection
evidence semantically; equality after excluding `rails_version` does not waive
the version check. The in-app
runtime oracle proves the actual family declarations; the pair probe separately
guards the Rails reflection assumptions used by the normalizer. Task specs own
malformed probe JSON and valid-JSON semantic mismatch paths.

## Planned files

- `lib/rails_mmd/relationship_metadata.rb`
- `lib/rails_mmd/relationship_builder.rb`
- `lib/rails_mmd/ir_builder.rb`
- `lib/rails_mmd/render_plan_builder.rb`
- `schemas/{ir,render_plan}.schema.json`
- `spec/rails_mmd/{relationship_metadata,relationship_builder,ir_builder,render_plan_builder}_spec.rb`
- `spec/contracts/schema_spec.rb` and v5 schema fixtures
- `spec/contracts/drift_guard_spec.rb`
- `tooling/rails_matrix.rb`
- `spec/integration/rails_matrix_task_spec.rb`
- `fixtures/rails_matrix/matrix.yml`
- `fixtures/rails_matrix/template/families/association_behavior/**`
- `README.md`
- `docs/active-record-association-support.md`
- `docs/p2/07-association-behavior-metadata/implementation.md`

## Acceptance criteria

- Every supported behavior declaration appears under the correct canonical
  endpoint direction, survives exact canonical dedup, and has stable ordering.
- Unsupported/invalid/unreadable behavior is absent without suppressing or
  mutating the structural relationship.
- HABTM echoes, inverse-only has-many counter naming, and ignored has-one-through
  dependent never appear as lifecycle behavior.
- IR and both render plans validate as v5; strict v4 output is not offered.
- Behavior-free relationship objects and all Mermaid text remain unchanged
  except for artifact top-level schema versions where applicable.
- All three pinned pairs produce identical normalized runtime/artifact meaning.
- Focused specs, complete RSpec, RuboCop, dependency audit, Undercover, every
  matrix family, pre-commit, and pre-push pass.

## Design contribution record

| Specialist lens | Contribution incorporated | Decision |
|---|---|---|
| Rails semantics | Pre-canonical direction table, outer-through-only behavior, inverse-name sanitization, normalized option active state, and macro-specific ignored Rails cases | accepted |
| Architecture/API | A deep normalizer/merge boundary, unchanged structural winner selection, separated polymorphic root/inverse fragments, atomic v5 migration | accepted; combined resolver and metadata merge into one cohesive `RelationshipMetadata` module |
| QA/testability | Public TDD slices for order/dedup and fail-soft behavior, full render-plan oracles, runtime/probe negative paths, and README drift guard | accepted |

## Design review record

| Round | Specialist lens | Findings resolved | Result |
|---|---|---|---|
| 1 | Rails semantics | No finding | `指摘なし` |
| 1 | Architecture/API | Limited schema claims to observable semantics, made IR projection one-way, and documented monkey-patched reflection-reader containment | corrected |
| 1 | QA/testability | Added explicit stale-v4 fixtures and exact locked-version probe validation | corrected |
| 2 | Rails semantics | No remaining finding | `指摘なし` |
| 2 | Architecture/API | No remaining finding | `指摘なし` |
| 2 | QA/testability | No remaining finding | `指摘なし` |
