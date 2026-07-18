# P2-05 Specialized Association Options Design

Status: complete

## Design objective

Replace option-presence omissions with exact Rails-reflected bindings for
`primary_key:`, explicit `source:`, polymorphic `source_type:`, and specialized
inverse `as:` declarations. Preserve every public schema, identifier,
cardinality rule, and previously emitted byte.

The implementation has two distinct responsibilities:

1. normalize unstable Active Record reflection readers into ordered physical
   bindings;
2. use those bindings inside the existing selection, domain, database-evidence,
   identity, and canonicalization pipeline.

Only the first responsibility is shared by both `SchemaProbe` and
`RelationshipBuilder`. It becomes one deep module. Through-path traversal has
one caller and remains private to `RelationshipBuilder` rather than becoming a
hypothetical seam.

## Adopted deep module

Add private module `RailsMmd::AssociationBindingResolver` in
`lib/rails_mmd/association_binding_resolver.rb` and require it from
`lib/rails_mmd.rb`.

### Interface

The module exposes three entry points:

```ruby
AssociationBindingResolver.belongs_to(reflection, target_model:)
AssociationBindingResolver.has(reflection, owner_primary_key_columns:)
AssociationBindingResolver.polymorphic_root(reflection)
```

All return one closed `Result`:

```ruby
Result = Struct.new(:binding, :diagnostic_code, keyword_init: true) do
  def success? = diagnostic_code.nil?
end

Binding = Struct.new(
  :foreign_key_columns,
  :referenced_key_columns,
  :foreign_type_column,
  keyword_init: true
)
```

Interface invariants:

- tuples are frozen, ordered `Array<String>` values from `KeyTuple`;
- `foreign_key_columns` is always present on success;
- `referenced_key_columns` is present for `belongs_to` and `has`, and absent
  only for `polymorphic_root` before a concrete target is known;
- `foreign_type_column` is present for `polymorphic_root` and for
  `belongs_to` when the reflection is polymorphic; `has` also returns it when
  the reflection is a polymorphic inverse (`options[:as]`), and returns `nil`
  for an ordinary direct has reflection;
- valid non-primary tuples are successful results;
- reader exceptions, invalid tuples, or unequal direct tuple widths return
  `ASSOCIATION_COMPOSITE_KEY_OMITTED`;
- the module does not resolve constants, inspect selected domains, read
  database constraints, construct diagnostics, or emit public objects.

### Hidden implementation

The module hides:

- the arity difference of `association_primary_key`;
- concrete-target-only calls for polymorphic `belongs_to`;
- `active_record_primary_key` plus owner-primary-key fallback;
- `foreign_key`, `foreign_type`, and inverse `type` reader selection;
- rescue wrapping around Active Record readers;
- scalar/composite normalization and equal-width validation.

`belongs_to` reads `foreign_key` plus
`association_primary_key(target_model)` and also carries `foreign_type` for a
polymorphic root. `has` reads `foreign_key` plus
`active_record_primary_key`, falling back only when that reader returns `nil`;
it also carries inverse `type` when `options[:as]` is present.
`polymorphic_root` reads `foreign_key` plus `foreign_type` and deliberately does
not read a referenced tuple.

The deletion test justifies this seam: without it, the same reader arity,
fallback, tuple, type-column, and rescue rules reappear in both `SchemaProbe`
and several `RelationshipBuilder` paths. Constant/domain/database behavior does
not pass the deletion test because it has only one owner and stays outside.

## Rejected alternatives

### Patch each option gate in place

Removing the current early returns would make valid examples green quickly but
leave four interpretations of the same reflection shape in direct, through,
polymorphic, and delegated code. The next composite or Rails-reader change
would drift again. Rejected for poor locality.

### Broad `ReflectionShape` object

A single object carrying association names, macros, scopes, through paths,
source typing, inverse aliases, keys, and root checks would expose nearly as
many facts as its implementation. Only relationship construction consumes the
through/path fields, so that portion would create a one-adapter hypothetical
seam. Rejected as a shallow module.

### Separate option-specific resolvers

`PrimaryKeyResolver`, `ThroughSourceResolver`, and `PolymorphicAliasResolver`
would mirror user-facing option names rather than Rails' physical binding
model. Callers would still need to combine results and precedence. Rejected
because it lowers leverage and spreads policy.

## Direct relationship flow

### `belongs_to`

1. Preserve name, target resolution, renderability, and same-domain checks.
2. Call `AssociationBindingResolver.belongs_to` with the concrete target model.
3. On resolver failure, emit its diagnostic code.
4. Require every owner foreign-key member and target referenced-key member.
5. Build the existing direct relationship with the returned tuples.

Delete the explicit `options[:primary_key]` omission from `build_reflection`.
No replacement option check is permitted.

### Direct `has_many` / `has_one`

1. Preserve target resolution and domain checks.
2. Call `AssociationBindingResolver.has` with the declaring owner's already
   probed `primary_key_columns` as fallback.
3. Require every target foreign-key member and owner referenced-key member.
4. Build and canonicalize with the existing macro priority.

Delete the `:non_primary_key` sentinel and the scalar actual-PK carveout from
`direct_key_columns`; replace all callers with the closed result.

### Identity and cardinality

The existing P2-04 tuple ID is authoritative:

```text
relationships/<holder_table>/<fk-segment>/<referenced_table>/<key-segment>
```

Scalar and existing composite IDs remain byte-identical. Newly eligible custom
keys use their reflected physical columns. Exact database FK, nullability, and
unique-index evidence remain unchanged; `primary_key:` itself never tightens
cardinality.

## Direct polymorphic and delegated flow

### Root shape

Both ordinary and delegated polymorphic roots call
`AssociationBindingResolver.polymorphic_root`. Remove eligibility checks that
require `<association>_id` and `<association>_type`; those names remain Rails
defaults only.

`SchemaProbe` uses the same result for delegated preflight. It checks only:

- sanitized association name;
- valid identifier tuple and scalar type column;
- presence of all identifier/type columns on the holder entity.

This call occurs only in the existing delegated-family discovery subphase,
after selected entity/schema probing is complete. It uses
`polymorphic_root`, which reads only `foreign_key` and `foreign_type` and never
calls `association_primary_key` or `active_record_primary_key`. P2-04's entity
probe boundary is therefore preserved; its wording is clarified alongside
this design.

Delete `default_polymorphic_keys?` and `primary_key_specialized?`. A delegated
family must not resolve a concrete referenced tuple during probing because the
tuple is target-specific.

### Concrete target binding

For each selected concrete target:

1. call `AssociationBindingResolver.belongs_to(root, target_model:)` to obtain
   the root identifier, reflected type column, and concrete referenced tuple;
2. for each inverse `has_many` / `has_one ..., as:`, call
   `AssociationBindingResolver.has`;
3. require exact equality of:
   - inverse `options[:as]` and root interface name;
   - holder child model;
   - identifier tuple;
   - type column;
   - referenced tuple;
4. require all holder and concrete target physical columns;
5. retain `has_one`, `has_many`, then lexical candidate canonicalization.

An exact custom binding succeeds. A resolved inverse/root mismatch is
`ASSOCIATION_POLYMORPHIC_OMITTED`, not
`ASSOCIATION_NON_PRIMARY_KEY_OMITTED`: P2-05 makes non-primary tuples eligible,
and the actual failure is binding disagreement. Invalid tuple shape remains
`ASSOCIATION_COMPOSITE_KEY_OMITTED`; missing physical columns remain
`ASSOCIATION_KEY_COLUMN_MISSING`.

Delegated type keeps all P2-03 provenance, whitelist, connection, domain,
renderability, partial-success, and metadata rules. Only root/candidate binding
changes.

## Through relationship flow

### Authoritative structural resolution

Remove the entry short-circuits for explicit `source:` and `source_type:`.
Resolve in this order:

1. sanitize the outer association name and safely capture `source_type:`;
2. safely read `through_reflection`;
3. safely read Rails' resolved `source_reflection`, classifying Rails
   typed-source validity exceptions before generic source failures;
4. validate the returned source reflection against the captured type;
5. safely read `collect_join_chain` and reverse to owner-forward order;
6. resolve/render/select every semantic path entity;
7. normalize path names and replace the terminal outer name with the resolved
   source-reflection name;
8. validate every physical hop;
9. publish the unchanged semantic through relationship.

Explicit `options[:source]` is never read as a target or placed in an ID. Its
only effect is already captured by Rails' `source_reflection`.

### Source typing

Source typing is valid only when:

- the resolved source reflection is polymorphic; and
- a present `source_type:` lets the outer `ThroughReflection` resolve one
  concrete target model.

A non-polymorphic source with `source_type:` or a polymorphic source without a
concrete type is `ASSOCIATION_POLYMORPHIC_OMITTED`.

If source resolution raises, classify by Rails exception class name on both
pinned versions:

- `AmbiguousSourceReflectionForThroughAssociation` and
  `HasManyThroughSourceAssociationNotFoundError` are
  `ASSOCIATION_SOURCE_UNRESOLVED`;
- `HasManyThroughAssociationPointlessSourceTypeError` and
  `HasManyThroughAssociationPolymorphicSourceError` are
  `ASSOCIATION_POLYMORPHIC_OMITTED`;
- any other source-reader exception is
  `ASSOCIATION_SOURCE_UNRESOLVED`.

The implementation compares stable exception class names without requiring
Rails exception constants at gem load time. When `source_reflection` returns,
the explicit source-polymorphic/type checks above remain authoritative.

Never call `klass` on the polymorphic source reflection. Resolve the concrete
model from the owning `ThroughReflection`, whose Rails `derive_class_name`
honors `source_type:`. This rule applies recursively to nested through paths.

### Private physical-hop descriptors

Replace `through_physical_reflections` with a private recursive helper that
returns descriptors:

```ruby
ThroughPhysicalHop = Struct.new(
  :reflection,
  :target_model,
  :target_constant,
  keyword_init: true
)
```

For an ordinary direct hop, resolve the target from that hop. For a polymorphic
terminal source, inject the concrete target resolved from its owning typed
`ThroughReflection`. Nested through reflections recurse while preserving the
owner-forward hop order and an identity-based cycle guard.

Each descriptor uses the shared binding resolver. A polymorphic physical hop
also requires its scalar type column on the holder. This closes the current
silent skip where raw target resolution fails on a polymorphic source and the
loop breaks without validating the terminal hop.

This descriptor remains a private implementation detail because only
`RelationshipBuilder` traverses paths.

### Path identity

Keep the existing public identity:

```text
relationships/<owner_table>/through/<resolved-path...>/<target_table>
```

Neither `source:` syntax nor the `source_type` value is appended. The selected
concrete target table and resolved source name already distinguish the semantic
path. Existing inferred-through IDs remain byte-identical.

## Diagnostic precedence

Apply this closed order for one declaration:

| Stage | Condition | Diagnostic |
|---|---|---|
| 1 | unsafe association name | `ASSOCIATION_NAME_UNSUPPORTED_OMITTED` |
| 2 | missing/raising through reflection | `ASSOCIATION_THROUGH_UNRESOLVED` |
| 3 | ambiguous/missing/raising source reflection or chain | `ASSOCIATION_SOURCE_UNRESOLVED` |
| 4 | invalid typed-source structure | `ASSOCIATION_POLYMORPHIC_OMITTED` |
| 5 | unresolved concrete target/type | `ASSOCIATION_TARGET_UNRESOLVED` |
| 6 | target not renderable | `ASSOCIATION_TARGET_NOT_RENDERABLE_OMITTED` |
| 7 | selected in another domain/connection | existing domain diagnostic |
| 8 | malformed or unequal tuple readers | `ASSOCIATION_COMPOSITE_KEY_OMITTED` |
| 9 | valid tuple with missing physical member | `ASSOCIATION_KEY_COLUMN_MISSING` |
| 10 | resolved polymorphic root/inverse binding mismatch | `ASSOCIATION_POLYMORPHIC_OMITTED` |

Reader exceptions map to the stage whose fact could not be established. Never
fall back from an explicit invalid option to inferred names or primary keys.
One failed target/alias remains local and does not suppress valid siblings.

## Public compatibility

- No JSON Schema change and no IR/render-plan version bump.
- No new relationship or metadata field.
- No Mermaid grammar change.
- No behavior option leaks into output; P2-07 owns those semantics.
- Existing direct, through, polymorphic, delegated, scoped, STI, composite, and
  HABTM outputs remain byte-identical.
- P2-06 domain/connection omissions remain unchanged.

## TDD vertical slices

Implementation follows `$tdd` one observable slice at a time.

### Slice 1: binding resolver

Red interface examples cover:

- scalar/composite `belongs_to` explicit referenced keys;
- scalar/composite `has_many` / `has_one` explicit referenced keys;
- inverse `as:` custom identifier/type columns;
- polymorphic root shape without a concrete target;
- reader exceptions, invalid tuples, and unequal widths.

Green adds the deep module only. These tests use small reflection doubles at the
module interface and do not test its private readers individually.

### Slice 2: direct public relationships

Red `RelationshipBuilder#build` examples replace current omission expectations
with exact public relationships for both orientations and all direct macros.
Add missing-column, DB-FK, uniqueness, inverse-canonicalization, and byte-stable
default regressions. Green removes option gates and sentinels.

### Slice 3: specialized polymorphic and delegated bindings

Red public-build and probe examples cover custom id/type/referenced keys,
`has_one`/`has_many` aliases, mismatch diagnostics, delegated inverse-free
fallback, and partial target success. Green shares the resolver and removes the
two default-name policies.

### Slice 4: explicit through source

Red public-build examples cover one-hop and nested explicit aliases, unchanged
path IDs, scopes, ambiguous/missing sources, cycles, and every physical hop.
They also pin option-free one-hop and nested inferred-through relationships and
diagnostics byte for byte before the private traversal replacement. Green
removes explicit-source omissions and follows resolved reflections without
changing the existing inferred path.

### Slice 5: typed polymorphic through source

Red examples cover valid scalar/custom and composite bindings, concrete target
injection, type-column presence, nested typed sources, invalid non-polymorphic
typing, missing type, unresolved constant, missing columns, and reader raises.
Green adds private physical-hop descriptors and staged diagnostics.

### Slice 6: real Rails matrix family

Add `fixtures/rails_matrix/template/families/specialized_options/` and register
it for all three declared pairs. Exact runtime and artifact oracles cover:

- scalar/composite custom direct keys for `belongs_to`, `has_many`, `has_one`;
- explicit source alias normalization;
- typed polymorphic source with custom id/type/referenced key;
- specialized direct `has_many` and `has_one ..., as:`;
- delegated type with explicit referenced key;
- real invalid cases Rails permits constructing.

The runtime oracle records exact reflection readers and successful association
loads. Generated relationship/diagnostic/IR/render-plan/Mermaid artifacts are
compared exactly. Unit doubles retain only impossible reader/error shapes.

### Slice 7: cumulative contract and durable knowledge

Update `docs/p0-contract.md`, the support matrix, README, and implementation
record. Add AGENTS guidance only for proven reusable rules:

- trust reflected key readers, not option presence;
- obtain a typed-through concrete target from its `ThroughReflection`, never a
  polymorphic source `klass`;
- keep source syntax out of public path identity.

## File-level plan

- add `lib/rails_mmd/association_binding_resolver.rb`;
- require it from `lib/rails_mmd.rb`;
- replace duplicated key/root policy in `lib/rails_mmd/schema_probe.rb`;
- replace option gates, sentinels, polymorphic matching, and through physical
  traversal in `lib/rails_mmd/relationship_builder.rb`;
- add `spec/rails_mmd/association_binding_resolver_spec.rb`;
- extend schema-probe, relationship-builder, and matrix-task specs;
- add the `specialized_options` real-app family and exact oracles;
- update cumulative contract/support/README/AGENTS documents;
- create `docs/p2/05-specialized-association-options/implementation.md` with
  red/green, specialist review, and hook evidence.

## Verification gates

For each slice:

- focused red proves the unsupported/incorrect behavior;
- focused green plus targeted RuboCop;
- relevant existing regression groups;
- exact real-Rails oracle regeneration only after unit/public seams are green.

Before completion:

- all RSpec examples;
- RuboCop;
- Bundler Audit;
- Undercover changed-line coverage;
- every declared Rails pair and fixture family;
- repository `pre-commit` and `pre-push` hooks.

## Specialist design record

The Rails specialist required reflected-shape resolution, concrete target
injection for typed polymorphic terminal hops, and removal of option-presence
eligibility. The interface specialist proposed closed results and unchanged
public contracts. A minimal-interface specialist proposed a broad captured
shape; comparison by depth, locality, and seam placement kept only its
anti-corruption-layer goal while narrowing the adopted interface to the three
binding operations shared by two callers.

## Design review record

Round 1 deep-module review required an explicit `has` inverse type-column
contract and byte-stable option-free through regressions before private
traversal replacement. Both were added; follow-up returned no findings.

Round 1 Rails review required typed-source exception classification before
generic source fallback, a concrete polymorphic `belongs_to` result carrying
its type column, and reconciliation with the P2-04 probe-phase rule. The design
now maps the four stable Rails exception class names, closes the binding
contract, and distinguishes selected entity/schema probing from the existing
delegated-family discovery subphase. The follow-up Rails review returned no
findings. All design perspectives are clear.
