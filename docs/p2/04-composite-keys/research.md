# P2-04 Composite Key Research

Status: complete

## Product boundary

The support matrix defines P2-04 as composite primary/foreign keys and
`query_constraints`, complete when corresponding ordered column sets are
retained and matched. The feature must compose with the direct, through,
polymorphic, HABTM, STI, delegated-type, and scope behavior already delivered.

P2-04 does not absorb these later rows:

- scalar custom `primary_key`, `source`, `source_type`, and specialized `as`
  resolution (P2-05);
- cross-domain and multi-database relationship publication (P2-06);
- behavioral options such as `dependent`, `touch`, and `counter_cache`
  (P2-07).

The distinction is structural rather than syntactic: P2-04 supports an ordered
set of physical key columns when Rails reflection establishes the matching set.
It does not infer an unrelated custom scalar column or override the existing
domain and connection boundaries.

## Verified Rails facts

Rails' composite-primary-key guide documents `primary_key: [:store_id, :sku]`
for a table and an association such as
`foreign_key: [:author_first_name, :author_last_name]`. The association's
foreign-key array and referenced-key array are positional; equal membership
with different order is not an equivalent relationship.

Pinned Rails 7.2.3.1 and 8.1.3 expose the normalized association columns through
reflection readers:

- `foreign_key` can return an ordered array;
- `active_record_primary_key` can return an ordered array on owner-side
  `has_one`/`has_many` paths for a composite owner key or the owner's
  query-constraint list;
- a `belongs_to` reflection's `association_primary_key(klass)` can return the
  target's ordered composite key or composite query-constraint list;
- Rails validates that paired key arrays have the same length when building the
  association join constraints.

Both pinned versions internally move an array-valued `foreign_key:` option to
`options[:query_constraints]`. The older association-level
`query_constraints:` spelling is version-sensitive:

- Rails 7.2.3.1 accepts it with a deprecation warning and advises using
  `foreign_key:` instead;
- Rails 8.1.3 raises `ActiveRecord::ConfigurationError` and advises using
  `foreign_key:` instead, although stale API comments still list the old
  option.

The common P2-04 contract must therefore use array `foreign_key:` or model-level
`query_constraints` in shared fixtures. A Rails-7.2-only probe may preserve the
deprecated spelling as compatibility evidence, but rails-mmd cannot make an
invalid Rails 8.1 model boot.

Model-level `query_constraints` affects record lookup, update, delete, and
ordering as well as association reflection. Rails reflection uses a model's
query-constraint list when deriving matching association columns. P2-04 reads
the resulting metadata; it must not execute queries to rediscover it.

A pinned-runtime probe confirmed the useful `belongs_to` contract in both
versions. For a composite target, `foreign_key`, `association_primary_key`,
`join_foreign_key`, and `join_primary_key` return the corresponding arrays. For
a scalar-primary-key target declaring `query_constraints :shop_id, :id`, those
same readers pair `['shop_id', 'basket_id']` with `['shop_id', 'id']`.
`active_record_primary_key` is `nil` on that `BelongsToReflection`; it is not a
valid substitute for the belongs-to-specific readers.

For a polymorphic `belongs_to`, `association_primary_key` must be called only
after a concrete target class is known and passed to the reader. Calling it on
the unresolved root attempts `self.klass` and raises `ArgumentError` in both
pinned versions. Generic root discovery must not use that reader.

A composite primary key containing `id` has a special Rails inference rule.
Unless the association explicitly requests the full key, Rails may infer the
single `id` column. rails-mmd must preserve the reflection result rather than
assuming that every array returned by `Model.primary_key` participates in every
association.

## Current repository behavior

`SchemaProbe` currently rejects every selected model whose `primary_key` is not
a non-empty string, emitting `MODEL_PRIMARY_KEY_UNSUPPORTED`. Its normalized
`Entity` stores a scalar `primary_key`. Database foreign-key metadata likewise
stores one `column` and one `primary_key` value.

Delegated-type family metadata is scalar too. `DelegatedTypeFamily` stores one
`foreign_key` and one `foreign_type`, populates them through scalar reflection
handling, and rejects a non-scalar delegated root on the existing
composite-key omission path before relationship publication.

Its normalized `DelegatedTypeFamily` also stores one scalar `foreign_key` next
to the scalar type discriminator, reads the root through the scalar-only seam,
and diagnoses a composite root before relationship publication. P2-04 must
widen the identifier side of that family metadata to an ordered tuple while
keeping the discriminator as one distinct column; otherwise delegated-type
composition would remain blocked before `RelationshipBuilder` can validate it.

`RelationshipBuilder` currently normalizes each reflection key through a
scalar-only guard. Direct, through, polymorphic, and HABTM paths consequently
emit `ASSOCIATION_COMPOSITE_KEY_OMITTED` before partially publishing an edge.
Its relationship record, physical identity, database-constraint matching,
nullability test, and unique-index test all assume one foreign-key column and
one referenced column.

`IRBuilder` marks one entity column as `primary_key` and obtains at most one
relationship foreign-key column. This loses both roles for a valid composite
relationship even if earlier layers were changed in isolation.

The public IR v3 and render-plan v3 relationship objects do not expose physical
key columns, and that relationship shape need not change. Their attribute
schemas do require a controlled evolution: one column can legitimately be both
a retained primary-key member and a published foreign-key member. Emitting two
rows would duplicate `attribute_id`/safe-token identity, while choosing either
role would lose information. P2-04 therefore moves IR and render-plan to v4,
adds one merged `primary_foreign_key` IR role and one `PK, FK` render marker,
and emits exactly one row for the physical column. Mermaid's official ER syntax
supports comma-separated key constraints such as `PK, FK`.

Some public identifiers nevertheless embed physical-key paths today. Direct
candidates are canonicalized through `canonical_relationship_id` to holder FK
and referenced-key segments. Polymorphic relationship IDs embed the holder
identifier plus type column, and polymorphic-group IDs mirror that segment
shape. Direct and polymorphic IDs therefore need a deterministic composite
tuple-segment grammar and matrix-oracle support. Through IDs are semantic path
IDs and remain unchanged. Composite HABTM is omitted in P2-04, so it introduces
no new public ID form. Scalar IDs of every kind remain byte-for-byte unchanged.
Composite direct and polymorphic IDs are additive contract cases
alongside the v4 attribute-role evolution. The v4 bump changes public
IR/render-plan documents globally, so exact scalar fixture churn is acceptable
only where it is caused by the schema-version advance itself; scalar entities,
relationships, diagnostics, grouping, and Mermaid text must otherwise remain
unchanged. Polymorphic-group tooling currently assumes a scalar identifier
segment and must be widened with that grammar.

## Accepted research boundary

The recommended P2-04 contract is:

- Normalize every physical key as a non-empty, frozen ordered array of distinct column
  names at the schema/reflection boundary. A scalar becomes a one-element
  array. Reject non-string members, empty members, empty arrays, nested arrays,
  and unequal paired lengths before relationship publication.
- Preserve Rails' reflected ordering. Use set-like comparison only where the
  database concept itself is unordered, such as checking whether a unique
  index covers exactly the required columns.
- Retain all selected composite-primary-key entities instead of diagnosing the
  model as unsupported. Mark every primary-key member in public attributes.
- Build a relationship only when the ordered foreign-key and referenced-key
  tuples are both present in their holder entities and have equal length.
- Include an unambiguous encoding of both ordered tuples in the internal
  physical relationship identity. Do not use delimiter joining that can
  collide for legal identifiers.
- Keep relationship IDs path-decomposable and retain every scalar grammar
  exactly. For direct IDs, encode each composite foreign/referenced tuple as
  one segment-safe, collision-free segment. For polymorphic IDs, encode the
  composite identifier tuple as one such segment and keep the scalar type
  segment unchanged. Derive tuple segments from the canonical JSON array using
  base64url without padding and an explicit tuple prefix. Through IDs stay
  key-agnostic. The design phase must pin the prefix and update fixture tooling
  to decode tuple segments instead of treating a tuple segment as one column.
- Determine tuple nullability conservatively: all participating foreign-key
  columns must be non-null before the relationship can be required. Preserve
  the P0 cardinality gate as well: a matching database FK is still required to
  strengthen a direct endpoint to `1..1`. Any nullable/unknown member or absent
  database evidence publishes the optional cardinality.
- Determine singularity from an exact total unique index covering the full
  holder tuple, plus the polymorphic type column when applicable. Partial
  indexes remain non-authoritative. Index column comparison follows the
  repository's existing order-independent rule.
- Match database foreign-key evidence only when the database metadata provides
  corresponding complete ordered column tuples. Absence of a composite
  database constraint does not suppress a valid Rails association; it only
  withholds database-constraint evidence.
- Apply the tuple contract to direct `belongs_to`, `has_one`, and `has_many`
  relationships and to existing through, polymorphic, and delegated-type paths
  wherever Rails supplies corresponding complete tuples. Unsupported or
  malformed shapes must fail as a whole, never publish a scalar subset, and
  keep the existing deterministic diagnostic boundary. Composite HABTM has the
  explicit pinned-runtime exception recorded below.
- Preserve the existing STI rule: endpoints remain physical base entities.
  Composite columns on an STI base still belong to that one physical entity.
- Preserve P2-06 boundaries. Composite metadata does not authorize cross-domain
  or different-connection probing.
- Preserve P2-05 boundaries. Unsupported specialized scalar `primary_key:` and
  other specialized options remain on their existing omission paths even
  though the same normalization machinery can represent one column. The
  already-supported direct-has case where Rails' reflected scalar key equals
  the owner's actual scalar primary key must remain supported.
- Do not add public key-tuple fields solely for P2-04. Ordered tuples stay
  internal, while v4 attributes expose every physical key role. Merge a
  dual-role physical column into one `primary_foreign_key` / `PK, FK` row; never
  emit duplicate attribute identities.
- Consume primary-key reflection readers only after schema probing has already
  established the participating models. Rails can fall through from these
  readers to `table_exists?` and schema-cache primary-key lookup when a model's
  key has not been initialized; P2-04 must not create an earlier discovery-time
  database-access path.
- Treat tuple-reader failures as association-level omissions, not inventory
  failures. If a composite-aware reflection reader raises or cannot establish a
  complete tuple at publication time, rails-mmd must keep the existing
  deterministic association diagnostic boundary and publish no partial edge.

## Association-shape expectations

### Direct associations

For `belongs_to`, the owner holds the reflected foreign-key tuple and the target
holds `association_primary_key(target)`. For `has_one` and `has_many`, the
target holds `foreign_key` and the owner holds `active_record_primary_key`.
These are positional pairs; model primary-key metadata is validation context,
not a replacement for reflection-specific results.

### Through associations

The published endpoint remains the logical owner-to-target relationship, while
physical key validation follows each source reflection in the chain. Every hop
must be valid as a complete tuple. A malformed hop invalidates the through
edge; no hop may be collapsed to its first column.

### Polymorphic and delegated associations

The type discriminator remains a separate column from the identifier tuple.
Each concrete target edge reuses the root foreign-key tuple and resolves its
target key tuple against that concrete class. Unique-index evidence covers
`[type_column] + foreign_key_columns` as one exact set. Rails-generated
delegated-type declarations retain the same constraints as their polymorphic
root; no synthetic composite convention is invented.

### HABTM associations

The hidden join table conceptually owns two complete foreign-key tuples, but
pinned Rails 7.2.3.1 and 8.1.3 do not provide an operational composite HABTM
contract. A real probe with explicit composite primary keys, `join_table`,
array `foreign_key`, and array `association_foreign_key` booted and exposed
arrays from `foreign_key`, `active_record_primary_key`,
`association_primary_key`, `join_primary_key`, and `join_foreign_key`.
Nevertheless, `association_foreign_key` stringified the supplied array, and
the generated association SQL degraded the owner predicate to a conventional
scalar `<model>_id` predicate in both versions. The unsaved-owner SQL also
contains `(1=0)`, but scalar HABTM can produce that guard too; it is not
composite-specific evidence and is not part of the capability decision.

The checked-in research evidence is the following exact shared-version shape:

```text
Book PK: [shop_id, book_id]
Author PK: [first_name, last_name]
Book foreign_key: [book_shop_id, book_book_id]
Book association_foreign_key: "[:author_first_name, :author_last_name]"
Book SQL owner column: p204_authors_books.p204_book_id
Author foreign_key: [author_first_name, author_last_name]
Author association_foreign_key: "[:book_shop_id, :book_book_id]"
Author SQL owner column: p204_authors_books.p204_author_id
```

The checked-in probe is
[`probes/composite_habtm_probe.rb`](probes/composite_habtm_probe.rb). Run it
once per declared pair using the same absolute `BUNDLE_PATH` convention as the
matrix runner. For example, the Ruby 4.0.6 / Rails 7.2 pair is:

```sh
BUNDLE_GEMFILE="$PWD/fixtures/rails_matrix/bundles/7.2/Gemfile" \
BUNDLE_PATH="$PWD/.bundle/rails-matrix/gems/4.0.6" \
ASDF_RUBY_VERSION=4.0.6 \
asdf exec bundle exec ruby \
  docs/p2/04-composite-keys/probes/composite_habtm_probe.rb
```

The probe returns both full-tuple flags as `false` and both scalar-fallback
flags as `true` on all three declared pairs. Implementation must keep it
reproducible and also validate the
no-edge/one-omission rails-mmd result on every pair.

P2-04 must therefore preserve scalar HABTM behavior but atomically omit
composite HABTM rather than diagram a relationship that neither pinned runtime
can execute correctly. This is a Rails-runtime capability boundary, not a
deferral of otherwise-supported tuple normalization. A future supported Rails
pair may reopen it with real SQL evidence. Join-table tuple members must never
be guessed from the stringified reader.

## Alternatives considered

### Keep scalar fields and add parallel composite-only fields

Rejected as the end-state contract. It creates two subtly different paths for
validation, identity, cardinality, and IR marking. Normalizing scalar keys to
one-element tuples provides one invariant and reduces regression surface.
Temporary compatibility accessors can be used during implementation, but they
must not remain independent sources of truth.

### Sort every key tuple

Rejected. Association joins are positional, so sorting can connect the wrong
columns while appearing deterministic. Only exact-index coverage is treated as
an unordered set.

### Publish the first column and warn about the remainder

Rejected. This produces a false relationship and violates the completion
condition that corresponding column sets be retained and matched.

### Add public relationship key-tuple fields

Rejected. The relationship contract intentionally abstracts physical columns,
and entity attributes plus deterministic IDs provide the required observable
result. The v4 bump is limited to the merged dual-role attribute value; it does
not add physical tuple arrays to public relationships.

## Acceptance and failure matrix

Required positive cases:

- a selected composite-primary-key entity is retained and every key member is
  marked `primary_key` in IR and both Mermaid formats;
- a column that legitimately serves both `primary_key` and `foreign_key` roles
  is projected exactly once as `primary_foreign_key` in IR and `PK, FK` in the
  render plan and ER Mermaid;
- direct `belongs_to`, `has_one`, and `has_many` pairs preserve two or more
  reflected columns in order and publish one stable logical edge;
- model-level `query_constraints` participates according to Rails reflection
  on every supported Ruby/Rails pair, including exact owner-side
  `active_record_primary_key` arrays for `has_one` and `has_many`;
- a composite association containing an `id` member follows the reflection's
  inferred scalar-or-tuple result rather than the model declaration alone;
- complete database-FK evidence plus an all-non-null foreign-key tuple produces
  required direct cardinality; a nullable/unknown member or absent database
  evidence produces optional cardinality;
- an exact total unique composite index proves singularity independent of index
  column order, while extra/missing columns and partial indexes do not;
- complete database composite-FK metadata is matched positionally when the
  adapter exposes it;
- valid through, polymorphic, and delegated-type composite shapes compose when
  their concrete reflection readers supply complete tuples;
- composite HABTM emits one deterministic composite-key omission and no edge on
  every pinned pair, while scalar HABTM artifacts remain unchanged. The exact
  runtime evidence is the checked-in composite HABTM probe above plus the
  eventual no-edge/one-omission fixture oracle or equivalent runtime proof;
- polymorphic-group artifacts remain deterministic with composite IDs: group-ID
  decoding, candidate grouping, and multi-column foreign-key attribute
  membership stay exact when a relationship ID carries an encoded tuple
  segment;
- reflection, model, index, and selection order do not change IDs, diagnostics,
  group order, or Mermaid output.
- scalar relationship IDs remain unchanged, and scalar-key generated IR and
  render-plan JSON are byte-for-byte unchanged except for `schema_version: 4`;
  scalar Mermaid, diagnostics, polymorphic groups, and relationship IDs are
  byte-for-byte unchanged. Composite tuple-segment grammar is introduced only
  for the public ID families that already encode physical key columns.
- tuple encoding cannot collide when legal column names contain punctuation or
  text resembling the tuple prefix.

Required partial/negative cases:

- a selected model with a missing, empty, duplicate, nested, non-string, or
  missing-column primary-key tuple remains a fatal
  `MODEL_PRIMARY_KEY_UNSUPPORTED` probe failure;
- empty, nested, non-string, or unequal-length key tuples emit exactly the
  established composite-key omission diagnostic when they come from an
  association reader and publish no partial edge;
- a raising or late-initializing tuple reader remains an association-level
  omission with a deterministic diagnostic, and never introduces earlier model
  discovery-time schema access;
- a referenced column missing on either side emits the existing missing-column
  diagnostic for the association and publishes no edge;
- a malformed or partially probed composite database-foreign-key row cannot
  invent tuple members, suppress an otherwise valid Rails relationship, or leak
  mixed partial evidence into the published edge;
- equal key members in different order are not accepted as corresponding
  relationship pairs;
- scalar custom non-primary keys remain deferred to P2-05;
- an association-level `query_constraints:` declaration is accepted only in a
  Rails 7.2-specific compatibility probe and is never loaded by the shared
  Rails 8.1 fixture;
- cross-domain and different-connection targets retain their existing omission
  behavior;
- ordinary scalar-key fixtures keep the same entities, relationships,
  diagnostics, grouping, and Mermaid text. Any scalar fixture churn is limited
  to the intentional IR/render-plan schema-version advance to v4. Concretely,
  scalar generated IR and render-plan fixtures may change only at the
  top-level `schema_version` field; all other scalar artifact content stays
  byte-for-byte unchanged.

## TDD and real-Rails evidence seams

- Begin with failing `SchemaProbe` public specs for composite entity retention,
  normalized database-key metadata, invalid tuple members, and stable ordering.
- Add failing `RelationshipBuilder` public specs per association family for
  positional tuple matching, missing columns, nullability, total uniqueness,
  database evidence, identity, and atomic failure.
- Add failing `IRBuilder` and contract specs proving every composite key member
  receives the correct public role, dual-role columns are merged, and both
  public documents use schema version 4.
- Extend the shared real Rails app with a composite-key family that uses only
  declarations valid on Rails 7.2.3.1 and 8.1.3. The exact runtime oracle should
  record the relevant reflection reader arrays as well as rails-mmd's
  relationship, diagnostic, and Mermaid outputs on every declared matrix pair.
- Implement that coverage as a `composite_keys` fixture-family overlay rather
  than altering the default family. Include one explicit composite-primary-key
  owner, one scalar-primary-key model with model-level query constraints,
  explicit direct `belongs_to`, `has_one`, and `has_many` declarations, a
  scope proc that raises if executed, one through chain composed only from
  already-valid tuple hops, one polymorphic holder whose composite identifier
  tuple is paired with a separate type column, and delegated-type coverage that
  proves the same tuple rules through either the existing `delegated_type`
  family or an explicit composite delegated fixture. Add the pinned composite
  HABTM declaration as a negative case with an exact one-warning/no-edge oracle;
  never execute the known-broken association query in rails-mmd.
- Wire that family through `fixtures/rails_matrix/matrix.yml`,
  `tooling/rails_matrix.rb`, and the matrix integration task spec before
  treating it as release evidence, so `verify:rails_matrix` really exercises
  the composite-key family on every declared pair.
- The family runtime oracle should record model `primary_key` and
  `query_constraints_list`, plus each association's `macro`, `foreign_key`,
  `association_primary_key`, `active_record_primary_key`, `join_primary_key`,
  `join_foreign_key`, and normalized `options[:query_constraints]`. Invoke
  target-sensitive readers only with the concrete class required by the
  polymorphic guard.
- Keep a small probe or explicit unit seam for the unresolved polymorphic-root
  failure mode so P2-04 proves the raw `association_primary_key` raise still
  collapses to a deterministic association omission instead of bypassing the
  existing diagnostic boundary.
- Add an instrumented unit seam proving association tuple readers are not
  invoked during inventory/schema probing, and that a publication-time reader
  raise is caught exactly once and mapped to the established association
  omission without partial output.
- Extend fixture validation to assert tuple-aware polymorphic-group artifacts,
  including composite group-ID decoding and the exact multi-column FK attribute
  set published for each group.
- Keep a Rails-7.2-only runtime probe for deprecated association-level
  `query_constraints:` if retained; do not normalize away its version boundary.
- Run scalar regression examples after each tuple-bearing path, then the full
  suite, contract checks, and every matrix pair.
- Add an explicit mismatch regression at the matrix-validator seam so
  `verify:rails_matrix` proves it rejects stale composite-ID decoding or stale
  polymorphic-group expectations instead of relying only on happy-path oracle
  files.
- The real matrix loads `db/schema.rb`, so treat it as evidence for Rails
  reflection and published artifacts, not as complete adapter-level composite
  database-foreign-key coverage. Prove exact database metadata normalization
  and mismatch behavior through `SchemaProbe` unit seams unless a supported
  adapter fixture demonstrably exposes complete arrays.

## Risks

- Treating ordered joins as sets can silently publish a false edge. Tuple order
  must survive normalization, physical identity, and database matching.
- Rails' `id`-containing composite-key inference differs from the raw model
  primary key. Reflection-specific readers are authoritative per association.
- Adapter database metadata may represent composite constraints differently or
  incompletely. Missing evidence must remain conservative rather than invented.
- A partial implementation can retain the entity but omit key roles, or publish
  the relationship while computing scalar cardinality. Tests must cross every
  layer from probing to exact Mermaid output.
- Stale Rails API comments list an association option rejected by Rails 8.1.
  Pinned executable behavior, not the stale comment, defines compatibility.
- Rails key readers can trigger schema access while initializing model primary
  keys. Moving them into inventory discovery would weaken the existing safe
  phase boundary; consume them only after probing and handle reader failures at
  the association diagnostic boundary.

## Sources

- Rails Composite Primary Keys Guide:
  <https://guides.rubyonrails.org/active_record_composite_primary_keys.html>
- Rails 7.2 Persistence `query_constraints` API:
  <https://api.rubyonrails.org/v7.2/classes/ActiveRecord/Persistence/ClassMethods.html>
- Mermaid ER attribute-key syntax:
  <https://mermaid.js.org/syntax/entityRelationshipDiagram.html#attribute-keys-and-comments>
- Pinned Rails 7.2.3.1 and 8.1.3 `active_record/reflection.rb` sources under the
  repository's matrix bundle.

## Research review record

| Round | Perspective | Findings | Correction |
|---|---|---|---|
| 1 | Rails runtime | Polymorphic reader safety and `active_record_primary_key` scope were too broad; composite HABTM lacked executable proof | Required a concrete polymorphic target, narrowed reader claims, and added the pinned HABTM probe |
| 1 | Architecture | Public ID migration and the existing direct-has scalar boundary were ambiguous | Pinned tuple segments for canonical direct/polymorphic IDs, unchanged through IDs, and preserved the accepted scalar direct-has case |
| 1 | QA / TDD | Dual-role attributes, reader failures, matrix wiring, group decoding, and mismatch tests were incomplete | Chose v4 merged roles and added deterministic unit, contract, fixture-family, runtime-oracle, and validator seams |
| 2 | Rails runtime | The unsaved-owner `(1=0)` SQL guard was not composite-specific evidence | Based the HABTM boundary only on the stringified reader, missing tuple predicates, and conventional scalar fallback |
| 2 | Architecture | Direct IDs and the HABTM exception still needed exact implementation/evidence anchors | Named `canonical_relationship_id`, committed the runnable probe, and fixed the matrix reproduction path |
| 2 | QA / TDD | None | — |
| 3 | Rails runtime | None | — |
| 3 | Architecture | None | — |
| 3 | QA / TDD | None | — |
