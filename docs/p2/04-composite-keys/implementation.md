# P2-04 Composite Key Implementation

Status: complete

## Delivered seams

### Ordered key tuples and relationship-ID codec

`RailsMmd::KeyTuple` is the single normalizer for model, reflection, adapter,
and delegated-family keys. Scalars become frozen one-element tuples; invalid,
duplicate, nested, or empty shapes are rejected. Structured physical identities
use canonical JSON.

`RailsMmd::RelationshipIdCodec` preserves every scalar direct/polymorphic ID and
encodes composite tuples with the full-grammar `tuple/<base64url>` production.
Its decoders validate kind, segment count, tuple shape, equal pair lengths, and
canonical re-encoding. A scalar column literally named `tuple` remains
unambiguous.

### Schema probing

`SchemaProbe` now carries only tuple fields:

- `Entity#primary_key_columns`;
- `ForeignKey#columns` and `#primary_key_columns`;
- `JoinTable#primary_key_columns`;
- `DelegatedTypeFamily#foreign_key_columns`.

Composite selected entities survive when every member exists. Invalid model
keys remain fatal; malformed optional adapter rows degrade without discarding
valid siblings. Association tuple readers remain outside the probe phase.

### Public schemas v4

IR and render-plan documents use schema version 4. Every key tuple member is
projected once. A physical column that is both PK and FK uses
`primary_foreign_key` in IR and `PK, FK` in the render plan/ER Mermaid. Scalar
fixtures change only at top-level `schema_version`.

### Relationship publication

`RelationshipBuilder` now stores only `foreign_key_columns` and
`referenced_key_columns`. Direct belongs-to/has associations consume their
Rails-specific readers, preserve model-level query-constraint tuples, and use
complete ordered pairs for identity, DB evidence, nullability, and exact unique
coverage. Composite direct and polymorphic IDs use the shared codec; through
IDs and all scalar IDs remain unchanged.

Polymorphic target keys are read only with a concrete target class. Delegated
families reuse the same tuple path while keeping the type discriminator scalar.
Every through hop must be tuple-valid. Composite HABTM remains an exact
one-warning/no-edge boundary, and scalar canonical label priority is preserved.

### Real Rails matrix family

The checked-in `composite_keys` family exercises composite direct, inverse,
polymorphic, delegated-type, through, query-constraint, combined PK/FK, and the
explicit HABTM omission boundary. Runtime and artifact oracles are exact rather
than presence-only. The complete manifest passed all three declared pairs and
all three fixture families:

```text
PASS ruby-4.0.6-rails-7.2 [default/delegated_type/composite_keys]
PASS ruby-3.3.12-rails-8.1 [default/delegated_type/composite_keys]
PASS ruby-4.0.6-rails-8.1 [default/delegated_type/composite_keys]
PASS 3/3 Rails matrix pairs
```

## TDD evidence

| Slice | Initial red | Green evidence |
|---|---|---|
| Key tuple | Missing helper, invalid-shape acceptance, missing pair/identity APIs | Codec/tuple examples pass with no offenses |
| Relationship ID codec | Composite encoding/decoder APIs absent; unequal pairs accepted | Scalar/composite round trips, collision and malformed payload examples pass |
| Composite entity | Valid composite PK emitted fatal `MODEL_PRIMARY_KEY_UNSUPPORTED` | `schema_probe_spec`: 37 examples, 0 failures |
| Adapter FK tuple | Array row produced no normalized `columns` | Complete tuples survive; malformed rows degrade; sibling evidence remains |
| Join-table PK tuple | Join-table result was not normalized | Nil/scalar/composite presence is deterministic |
| Delegated root tuple | Composite identifier emitted `ASSOCIATION_COMPOSITE_KEY_OMITTED` | Tuple identifier plus scalar type survives the probe fence |
| IR v4 tuple projection | Only one scalar PK/FK member was emitted | All members and merged roles are exact |
| Render-plan v4 | Combined marker/schema value was rejected | `PK, FK` and closed v4 fixtures pass |
| Direct relationships | Obsolete scalar entity key calls raised; composite edge was absent | Ordered pairs publish with exact evidence and scalar IDs unchanged |
| Polymorphic relationships | Composite root emitted `ASSOCIATION_COMPOSITE_KEY_OMITTED` | Concrete targets publish tuple IDs without unresolved-root key reads |
| Through atomicity | An invalid composite hop still published the semantic edge | One invalid hop omits the through edge without affecting valid direct hops |
| Composite HABTM | Array readers could fall into scalar/missing-column paths | Exactly one composite omission and no edge; scalar HABTM unchanged |
| Safe failure and through-hop branches | Undercover reported seven changed methods, then one remaining composite physical-hop branch | Focused behavioral examples cover invalid introspection, incomplete tuples, explicit non-primary keys, and complete/missing physical hops |
| Review: scalar through hops | Missing columns and explicit scalar `primary_key:` passed an early scalar return | Two red regressions now require physical columns and preserve the P2-05 omission boundary for every hop |
| Review: inverse-free delegated fallback | A two-member root could publish against a one-member target tuple | Equal tuple length is required before publication; missing physical target columns use `ASSOCIATION_KEY_COLUMN_MISSING` |
| Review: polymorphic singularity | A selected `has_one` inverse upgraded cardinality without database uniqueness | Only an exact unique index over identifier tuple plus type column yields `0..1` |
| Hook: decoder branch coverage | Undercover reported unverified malformed-grammar exits and scalar polymorphic decoding | Full grammar rejection and scalar round-trip examples cover every changed decoder branch |

Exact completed slice gates:

```text
key_tuple_spec + relationship_id_codec_spec: 14 examples, 0 failures
schema_probe_spec: 37 examples, 0 failures
ir_builder_spec + render_plan_builder_spec + contracts: 56 examples, 0 failures
relationship_builder_spec: 58 examples, 0 failures
combined spec/rails_mmd + spec/contracts: 308 examples, 0 failures
targeted RuboCop for each completed slice: no offenses
rails_matrix_task_spec: 36 examples, 0 failures
verify:rails_matrix: 3/3 pairs, 9/9 family runs passed
latest full rake gate: 373 examples, 0 failures; 129 files, no offenses
bundler-audit: no vulnerabilities found
Undercover: no coverage missing in latest changes
pre-commit hook: passed
pre-push hook: passed
```

## Verification record

Targeted relationship, schema, matrix, and contract gates are green. The full
Rake gate, dependency audit, changed-line coverage gate, and all nine real-Rails
family runs are green. Both repository hooks and all specialist-review gates
passed.

## Implementation review record

Round 1 found three actionable boundaries:

- Rails and architecture reviews found scalar through hops bypassing physical
  column and explicit `primary_key:` checks;
- Rails review found missing tuple-pair validation in inverse-free delegated
  fallback;
- QA review found polymorphic/delegated singularity inferred from inverse macro
  rather than exact database uniqueness.

All three were reproduced with five failing examples before production changes,
then repaired. Existing through fixtures were made physically complete instead
of weakening the new validation. The relationship suite is green at 72 examples,
and the exact matrix integration suite is green at 36 examples after refreshing
cardinality oracles and their canonical digests.

Round 2 found no further production defect, but found three verification and
contract gaps:

- the real-Rails runtime oracle covered only one of two concrete targets for a
  polymorphic root;
- composite inverse-free delegated column absence and scalar through omissions
  lacked public-build coverage;
- the cumulative P0 contract still described the pre-P2-04 scalar polymorphic
  and `has_one`-driven cardinality boundary.

The runtime oracle now records the concrete target and target-specific
`association_primary_key` for every polymorphic target. Public-build examples
cover the two scalar through omissions, and a composite delegated example
covers equal-length tuples with a missing target member. The cumulative
contract now documents composite polymorphic IDs and exact-unique cardinality.
The relationship suite is green at 75 examples and the exact matrix integration
suite remains green at 36 examples.

Round 3 Rails and QA reviews returned no findings. Architecture review found
that JSON Schema `uniqueItems` rejects only identical attribute objects and did
not enforce the promised identity uniqueness when duplicate `attribute_id`
rows differed in other fields. The invalid fixtures now use that adversarial
shape, and `SchemaValidator` adds deterministic post-schema identity validation
for both IR and render plans. The focused schema/primitives gate is green at 33
examples.

Round 4 found two remaining contract boundaries:

- identity tracking was reset per entity, so a repeated `attribute_id` across
  two entities still passed;
- the cumulative contract and support-summary bullets still described direct
  associations as scalar-only.

Cross-entity adversarial fixtures now fail before the fix and pass the contract
gate after document-wide identity tracking. The cumulative relationship
contract now specifies equal-length direct tuples and the tuple ID grammar, and
the support summary records composite direct/polymorphic support plus the
composite-HABTM omission boundary.

Round 5 Rails and architecture reviews returned no findings. QA found two stale
verification surfaces: the cumulative render-plan example still showed v1 and
the fake-system matrix cases selected composite keys only on Rails 8.1. The
example now shows v4 with `inheritances`, and an explicit Rails 7.2
`composite_keys` case exercises the version-specific runtime-probe branch.

Round 6 Rails and QA reviews returned no findings. Architecture review found one
stale blocking-fixture row that still listed composite primary keys as
unsupported. It now limits `MODEL_PRIMARY_KEY_UNSUPPORTED` to missing, empty,
nested, duplicate-member, or otherwise invalid key metadata.

Round 7 architecture review returned no findings. Rails review identified an
apparent code/contract conflict for explicit scalar `primary_key:` on direct
has associations. The implementation matches the approved P2-04 design: the
pre-existing scalar case is retained only when it equals the owner's actual
scalar primary key. The cumulative contract wording introduced in round 4 was
too broad and now records that exact exception; all other specializations stay
on the P2-05 boundary.

The follow-up Rails review confirmed the corrected contract and returned no
findings. The final architecture review also returned no findings, and the
preceding QA review returned no findings before the documentation-only cleanup.
The pre-push coverage gate then exposed missing decoder examples; full-grammar
rejection and scalar polymorphic round-trip coverage were added and the hook
passed. The final focused QA review returned no findings. All specialist
perspectives and repository hooks are clear.
