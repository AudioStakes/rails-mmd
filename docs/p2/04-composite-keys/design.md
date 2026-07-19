# P2-04 Composite Key Design

Status: complete

## Goals

- Retain selected models with composite primary keys.
- Preserve and positionally match complete reflected foreign/referenced column
  tuples for direct, through, polymorphic, and delegated-type relationships.
- Support array `foreign_key:` declarations and model-level
  `query_constraints` on every declared Ruby/Rails pair.
- Compute identity, cardinality, database evidence, and public key attributes
  from the complete tuple without scalar fallback.
- Preserve every scalar relationship ID and scalar artifact byte-for-byte,
  except for the intentional IR/render-plan schema-version advance to v4.
- Keep the pinned composite HABTM runtime boundary executable and explicit.

## Non-goals

- Specialized scalar `primary_key`, `source`, `source_type`, or custom
  polymorphic identifier/type resolution (P2-05).
- Cross-domain or cross-connection publication (P2-06).
- Behavioral association options (P2-07).
- Publishing physical tuple arrays on public relationship objects.
- Guessing composite database constraints or HABTM join columns that the
  adapter or Rails reflection does not expose completely.

## Pipeline

```text
Rails model/schema metadata
  -> KeyTuple.normalize
  -> SchemaProbe
       Entity.primary_key_columns
       ForeignKey column tuples
       DelegatedTypeFamily identifier tuple + scalar type
  -> RelationshipBuilder
       reflection-specific ordered tuple pairs
       canonical physical identity
       tuple cardinality/evidence
       direct/polymorphic public ID codec
  -> IR v4
       one attribute per physical column
       primary_key / foreign_key / primary_foreign_key
  -> render plan v4
       PK / FK / PK, FK
  -> existing Mermaid serializers
```

All tuple-bearing state is internal. Public relationship objects retain their
v3 field shape. The v4 change is the closed attribute-role/marker extension and
the top-level schema version.

## Shared key-tuple contract

Add `RailsMmd::KeyTuple` in `lib/rails_mmd/key_tuple.rb`.

```ruby
normalize(value) # frozen Array<String> or nil
valid_pair?(foreign_columns, referenced_columns)
identity(payload) # canonical JSON string
```

`normalize` implements one invariant:

- a non-empty string becomes a frozen one-element array;
- an array remains in supplied order and is copied/frozen;
- an empty array, empty member, non-string member, nested array, or duplicate
  member returns `nil`;
- symbols are not coerced at this boundary because Rails public readers already
  return column-name strings and silent coercion would hide malformed doubles
  or adapter rows.

Every model, reflection, adapter, and delegated-family key passes through this
helper. No later code sorts a relationship tuple. `valid_pair?` requires two
valid tuples of equal length. Unique-index coverage alone compares an unordered
exact set because index order does not alter uniqueness.

`identity` delegates to the existing `CanonicalJson.dump`. Physical identity
uses structured arrays/hashes, never delimiter-joined strings.

## Public relationship-ID codec

Add `RailsMmd::RelationshipIdCodec` in
`lib/rails_mmd/relationship_id_codec.rb`. It owns encoding and decoding for
production builders and matrix tooling.

A single prefixed segment cannot be collision-free while every legal scalar
column segment must remain unchanged: a scalar column could equal that encoded
text. Use an extra structural marker segment instead:

```text
scalar-key-segments    := <column>
composite-key-segments := tuple/<base64url-no-padding(canonical-json-array)>
```

The complete ID grammar, rather than a local marker test, makes scalar and
composite forms disjoint. Equal-length association pairs mean a direct scalar
ID has five total segments and a composite direct ID has seven; a polymorphic
composite ID has exactly one more segment than its scalar form. A scalar column
named `tuple` therefore remains scalar at the scalar grammar's total length.
Decoder rules are:

- choose the scalar or composite production from the complete relationship
  kind and total segment count, never from the text `tuple` alone;
- one ordinary segment in the scalar production decodes as a scalar tuple;
- `tuple/<payload>` must base64url-decode to canonical JSON containing a valid
  tuple of at least two members;
- malformed marker/payload input raises a codec error and never degrades to a
  scalar;
- encoding the decoded tuple must reproduce the exact payload.

Public grammars are:

```text
direct:
relationships/<holder_table>/<key_segments(fk)>/
  <referenced_table>/<key_segments(referenced)>

polymorphic:
relationships/<holder_table>/polymorphic/<interface>/
  <key_segments(identifier)>/<type_column>/<target_table>

polymorphic group:
the polymorphic relationship ID without <target_table>
```

Scalar calls emit their existing single column segment and therefore preserve
current IDs. Through IDs remain
`relationships/<owner>/through/<path...>/<target>`. Composite HABTM emits no
relationship. Scalar HABTM keeps its current grammar.

## SchemaProbe contract

The normalized records become:

```ruby
Entity = Struct.new(
  :ruby_constant,
  :table_name,
  :connection_context_id,
  :columns,
  :primary_key_columns,
  :foreign_keys,
  :indexes,
  :selection_origin,
  keyword_init: true
)

ForeignKey = Struct.new(
  :from_table,
  :columns,
  :to_table,
  :primary_key_columns,
  keyword_init: true
)

JoinTable = Struct.new(
  :table_name,
  :columns,
  :primary_key_columns,
  keyword_init: true
)

DelegatedTypeFamily = Struct.new(
  # existing identity/status fields,
  :foreign_key_columns,
  :foreign_type,
  keyword_init: true
)
```

Do not retain scalar aliases. Tests and downstream code must move to the tuple
fields so one representation remains authoritative.

### Selected entities

Read `model.primary_key` once in the existing probed-model phase and normalize
it. A valid tuple must be non-empty, distinct, and wholly present in the probed
columns. Failure remains fatal `MODEL_PRIMARY_KEY_UNSUPPORTED` with exit code 2.
Scalar models become one-element tuples and otherwise keep existing behavior.

Schema probing may initialize model primary-key metadata as it already does.
It must not call association-specific `foreign_key`,
`association_primary_key`, or `active_record_primary_key` readers. An
instrumented spec pins that phase boundary.

### Adapter foreign keys

Normalize adapter `column` and `primary_key` values independently, then require
an equal-length pair. Table names remain non-empty strings. Any malformed row
uses the existing degraded-metadata path and cannot publish partial database
evidence. Valid rows from the same adapter response survive.

Absence of adapter composite-FK support does not omit a reflected Rails
relationship. It only makes `db_foreign_key` false.

### Join tables

Normalize a non-nil join-table primary key so ambiguity checks can distinguish
nil from scalar/composite presence. Scalar HABTM discovery otherwise stays
unchanged. P2-04 never interprets the stringified composite
`association_foreign_key` reader.

### Delegated roots

Normalize the polymorphic identifier reader into `foreign_key_columns`; keep
`foreign_type` as one structured scalar column. A scalar identifier must still
match `<role>_id`. A composite identifier is allowed when Rails returns the
complete ordered array. The type must still match `<role>_type`, and explicit
`primary_key:` specialization remains deferred.

Missing identifier members produce `ASSOCIATION_KEY_COLUMN_MISSING`. Malformed
identifier tuples produce `ASSOCIATION_COMPOSITE_KEY_OMITTED` before family
expansion. Provenance, whitelist, exclusion, domain, connection, and expansion
fences remain unchanged.

## RelationshipBuilder contract

The final `Relationship` physical mapping is:

```ruby
foreign_key_holder_entity_id
foreign_key_columns       # frozen tuple or nil
foreign_type_column       # scalar discriminator or nil
referenced_key_columns    # frozen tuple or nil
physical_key              # canonical JSON identity
```

Remove `foreign_key_column`, `referenced_primary_key_column`,
`owner_foreign_key_column`, and `target_primary_key_column`. Through and HABTM
relationships can leave the tuple fields nil. The logical owner/target,
association metadata, cardinalities, and public relationship shape remain
unchanged.

Physical direct identity is the canonical JSON of:

```ruby
{
  kind: 'direct',
  holder_entity_id:,
  foreign_key_columns:,
  referenced_entity_id:,
  referenced_key_columns:
}
```

Polymorphic identity additionally contains interface and type column. Through
and scalar HABTM identity move to canonical structured payloads without
changing their public IDs.

### Direct `belongs_to`

- holder tuple: `reflection.foreign_key`;
- referenced tuple: `reflection.association_primary_key(target_model)`;
- never use `active_record_primary_key` for this macro;
- normalize and require equal length;
- require every holder and target member column to exist.

Trust the target-specific reflection reader. Do not require the tuple to equal
the model's raw primary key, because target model-level `query_constraints` can
legitimately produce a wider tuple. Explicit `options[:primary_key]` remains on
the existing P2-05 omission path.

### Direct `has_one` / `has_many`

- holder tuple on the target: `reflection.foreign_key`;
- referenced tuple on the owner: `reflection.active_record_primary_key`;
- if the reader is nil, fall back only to the already-probed owner tuple;
- normalize and require equal length and present columns.

Do not compare a reflected tuple to the raw owner primary key for ordinary
support decisions; model-level `query_constraints` may widen it. If an explicit
`primary_key:` option exists, preserve the current accepted scalar case only
when the reflected one-element tuple equals the owner's one-element actual
primary key. All other explicit specializations remain
`ASSOCIATION_NON_PRIMARY_KEY_OMITTED` until P2-05.

### Reader failure boundary

Tuple readers run only during relationship publication. A nil, invalid, or
raising reader produces one `ASSOCIATION_COMPOSITE_KEY_OMITTED` and no partial
edge. The only nil exception is direct `has_one`/`has_many`
`active_record_primary_key`, which uses the already-probed owner tuple as
specified above. A resolved target must not be reclassified as unresolved
because a later key reader failed.

### Through associations

Keep the existing semantic owner-to-target edge and normalized path ID. Validate
each underlying direct hop with the same tuple reader and column-presence rules.
One invalid hop atomically omits the through edge. Existing direct physical
edges remain independently eligible. `source` and `source_type` stay deferred.

### Polymorphic and delegated associations

Normalize the root `foreign_key` as the identifier tuple and keep
`foreign_type` scalar. Resolve the referenced tuple separately for each known
concrete target with `association_primary_key(concrete_target_model)`; never
call it on the unresolved root. Matching inverses use their ordered
`foreign_key` and `active_record_primary_key` readers as evidence. The inverse
scalar `type` reader must equal the root `foreign_type`; a custom or mismatched
type is not candidate evidence and remains on the existing omission boundary.

The concrete edge requires equal identifier/referenced lengths and all physical
columns. Its ID uses the composite codec only when the identifier has multiple
members. Delegated whitelist authority and inverse-optional behavior remain
unchanged.

### HABTM

If either HABTM key reader is non-scalar, emit exactly one
`ASSOCIATION_COMPOSITE_KEY_OMITTED` and no edge. Do not parse the stringified
array. Scalar HABTM probing, ambiguity checks, canonicalization, and exact
artifacts stay unchanged. The checked-in runtime probe and matrix negative
oracle make this boundary executable on every pair.

## Cardinality and database evidence

- Tuple nullability evidence is true only when every holder member has
  `nullable == false`. Missing/unknown/nullable members make it false.
- Direct singularity requires one total, plain, unique index whose column set
  exactly equals the holder tuple.
- Polymorphic/delegated singularity requires exact unique coverage of
  `foreign_key_columns + [foreign_type_column]`.
- Index order is ignored; missing, extra, expression, partial, or unsupported
  rows are not evidence.
- Database FK evidence requires matching holder/referenced table names and
  exactly equal ordered column tuples.
- Preserve the P0 public cardinality gate: a direct endpoint becomes `1..1`
  only when tuple nullability evidence is true and an exact database FK exists.
  Missing database evidence keeps that endpoint optional but never suppresses
  the valid reflected association.

## IR and render-plan v4

`IrBuilder` builds a role set by physical column name:

1. add `:primary` for every entity primary-key member;
2. add `:foreign` for every published relationship whose holder is the entity,
   including every identifier member and the polymorphic type column;
3. emit one attribute row per name.

Map role sets as follows:

| Roles | IR role | Render marker |
|---|---|---|
| primary | `primary_key` | `PK` |
| foreign | `foreign_key` | `FK` |
| primary + foreign | `primary_foreign_key` | `PK, FK` |

Primary-bearing rows sort before FK-only rows, then by `attribute_id`. No two
rows share an `attribute_id`. `MermaidSerializer` already emits a marker string
verbatim, and Mermaid officially accepts `PK, FK`; no serializer branch is
needed.

Update both schema constants to 4 and extend only the closed role/marker enums.
Every scalar valid fixture changes only its top-level schema version. Add v4
dual-role valid fixtures and invalid fixtures for stale v3, illegal combined
values, and duplicated identities.

Referenced query-constraint members that are neither actual PK nor holder FK
remain internal relationship mapping; they are not mislabeled as PK. They can
still appear when they independently hold a published FK. P2-04 does not invent
a Mermaid key marker for Rails query constraints.

## Real Rails matrix family

Add `composite_keys` to `fixtures/rails_matrix/matrix.yml` and create
`fixtures/rails_matrix/template/families/composite_keys/`.

The shared family uses only declarations valid on Rails 7.2.3.1 and 8.1.3:

- a two-column primary-key parent and direct belongs-to/has-many children;
- a dual-role child whose composite PK is also the holder FK;
- a scalar-PK target with model-level `query_constraints`;
- direct `has_one`/`has_many` query-constraint coverage;
- an `id`-containing composite inference case;
- one through chain composed from valid tuple hops;
- a polymorphic holder with composite identifier tuple and scalar type;
- delegated-type tuple coverage, reusing or extending the delegated family;
- one raising scope proc that must never execute;
- the composite HABTM declaration as a one-warning/no-edge negative case.

Add `rails_mmd_composite_runtime_oracle.rb` and an exact expected JSON file. For
each model/association, record model primary/query-constraint lists and the
applicable `macro`, `foreign_key`, `association_primary_key(target)`,
`active_record_primary_key`, `join_primary_key`, `join_foreign_key`, and
normalized `options[:query_constraints]`. Do not call a target-sensitive reader
without its concrete target and do not execute the HABTM association query.

Replace the current delegated-type-only conditionals with closed dispatch
tables owned by the runner:

```ruby
FAMILY_RUNTIME_ORACLES = {
  'delegated_type' => { script: ..., expected: ..., validator: ... },
  'composite_keys' => { script: ..., expected: ..., validator: ... }
}.freeze

PAIR_PROBES = {
  'composite_keys' => { script: 'docs/.../composite_habtm_probe.rb', validator: ... }
}.freeze
```

Unknown configured families and missing/malformed/mismatched expected runtime
files fail verification. `verify:rails_matrix` executes the checked-in HABTM
probe under each pair's selected Ruby, Gemfile, and absolute bundle path before
accepting that pair's `composite_keys` family. Its validator requires the
locked Rails version, both full-tuple flags `false`, and both scalar-fallback
flags `true`. This is an automated matrix gate, not a manual release step.

`tooling/rails_matrix.rb` also requires the shared ID codec. The polymorphic-group
projector decodes the identifier tuple structurally and selects every matching
FK attribute plus the scalar type attribute. Malformed payloads fail
verification. Integration specs must prove stale runtime oracles, tuple
decoding, group membership, and missing family wiring fail.

The family produces exact relationships, diagnostics, groups, IR/render-plan,
ER Mermaid, and class Mermaid oracles on all three pairs. Integration specs
must first fail for missing dispatch, missing/malformed/mismatched composite
runtime output, and failing pair-probe flags, then pass with the complete table.

## TDD vertical slices

1. `KeyTuple` red/green: scalar normalization, order/freeze, invalid tuples,
   equal-length pairs, canonical identity.
2. `RelationshipIdCodec` red/green: scalar byte stability, composite round
   trip, malformed payload, punctuation/prefix collisions.
3. `SchemaProbe` red/green: composite entity retention, fatal invalid PKs,
   adapter tuple normalization/degradation, delegated root tuple, phase fence.
4. Direct `belongs_to` red/green: tuple match, missing/order cases, DB evidence,
   nullability, uniqueness, canonical ID, scalar regression.
5. Direct `has_one`/`has_many` red/green: query constraints, `id` inference,
   target-side holder logic, reader raise, scalar explicit-PK regression.
6. Polymorphic red/green: concrete-target reader safety, identifier/type
   matching, exact uniqueness, IDs, and scalar regression.
7. Delegated-type red/green: tuple family handoff, authoritative whitelist,
   inverse-optional behavior, and scalar family regression.
8. Through red/green: each physical hop valid, atomic semantic omission, and
   unchanged path IDs.
9. HABTM red/green: exact composite omission/no edge and scalar byte stability.
10. IR/render-plan v4 red/green: all tuple members, one merged dual-role row,
   combined marker, closed-schema fixtures, scalar version-only diff.
11. Polymorphic-group tooling red/green: scalar projection stability,
    composite tuple decoding, exact FK membership, malformed payload failure.
12. Matrix red/green: family dispatch, runtime oracle, exact outputs, mismatch
    rejection, all three pairs, and the automated standalone probe.

Each slice starts with the smallest failing public spec, records the red output
in the implementation note, implements only that seam, and reruns the affected
spec plus a scalar regression before continuing.

## File-level implementation plan

| File | Responsibility |
|---|---|
| `lib/rails_mmd/key_tuple.rb` | One tuple normalization/identity invariant |
| `lib/rails_mmd/relationship_id_codec.rb` | Scalar-stable composite ID encode/decode |
| `lib/rails_mmd/schema_probe.rb` | Model, adapter, join-table, delegated tuple normalization |
| `lib/rails_mmd/relationship_builder.rb` | Reflection tuple pairs, evidence, identity, IDs, omissions |
| `lib/rails_mmd/ir_builder.rb` | All key members and merged v4 roles |
| `lib/rails_mmd/render_plan_builder.rb` | v4 marker mapping |
| `schemas/{ir,render_plan}.schema.json` | Closed v4 contracts |
| `fixtures/schemas/**` | v4 valid/invalid exact fixtures |
| `tooling/rails_matrix.rb` | Family runtime validation and tuple-aware group projection |
| `fixtures/rails_matrix/**` | Composite family, runtime oracle, exact artifacts |
| `spec/rails_mmd/**` | Unit/public behavior for every tuple-bearing seam |
| `spec/contracts/**` | v4 closed-schema proof |
| `spec/integration/rails_matrix_task_spec.rb` | Family and mismatch enforcement |
| `README.md`, `docs/active-record-association-support.md` | Public version/support status |
| `AGENTS.md` | Durable Rails-version and reader-safety knowledge |

## Verification gates

- Every tuple slice: affected spec file plus one scalar regression.
- Contract gate: all schema fixtures and `spec/contracts` pass at v4.
- Default gate: RuboCop, full specs/coverage, Bundler Audit, Undercover.
- Runtime gate: all three pairs across `default`, `delegated_type`, and
  `composite_keys` families.
- Probe gate: the composite HABTM probe returns no full owner tuple and a scalar
  fallback on all pairs.
- Repository gate: direct `pre-commit`, then direct `pre-push`.

## Design review record

| Round | Perspective | Findings | Correction |
|---|---|---|---|
| 1 | Rails runtime | Direct cardinality language blurred tuple nullability and the P0 DB-FK gate; inverse type matching was absent | Restored the exact P0 cardinality rule and required inverse `type == foreign_type` |
| 1 | Architecture | Tuple marker decoding and direct-has nil fallback were ambiguous | Made decoding depend on the full kind/segment-count grammar and carved out the single nil fallback |
| 1 | QA / TDD | Runtime-oracle routing was hard-coded, the multi-feature slice was too wide, and the HABTM probe was manual | Added closed family/pair-probe dispatch, split the public seams, and made the probe part of matrix verification |
| 2 | Rails runtime | None | — |
| 2 | Architecture | None | — |
| 2 | QA / TDD | None | — |
