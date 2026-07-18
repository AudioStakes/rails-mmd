# P1-06 Polymorphic Associations Design

Status: design complete and reviewed

## Decisions

### Two-pass inventory

- Inventory every selected entity's reflections before building relationships.
- Defer direct polymorphic `belongs_to` roots and direct inverse
  `has_many`/`has_one ..., as:` reflections from normal direct classification.
- Build ordinary direct and through relationships unchanged, then resolve
  polymorphic groups from the deferred inventory.
- A group requires one actual polymorphic `belongs_to` root. An unmatched
  unscoped inverse `as:` reflection remains `ASSOCIATION_POLYMORPHIC_OMITTED`
  and never invents a root; a scoped inverse remains
  `ASSOCIATION_SCOPED_OMITTED`.

### Root eligibility

- Root must be direct, unscoped, safely named, and selected.
- `foreign_key` and `foreign_type` must each be one non-empty string.
- Both columns must exist on the holder entity. Missing either reuses
  `ASSOCIATION_KEY_COLUMN_MISSING` and omits the complete group.
- Scoped roots reuse `ASSOCIATION_SCOPED_OMITTED`; composite/custom-key shapes
  reuse the existing key omission paths where applicable.
- The root's concrete `klass` is never read.

### Candidate matching

- Candidate owner and root holder must both be selected same-domain entities.
- A candidate reflection must be direct, unscoped `has_many` or `has_one` with
  `options[:as]` equal to the root interface.
- Its fixed child `klass` must resolve to the root holder entity.
- Its scalar `foreign_key` and scalar `type` must equal the root id/type columns.
- Its `active_record_primary_key` must equal the candidate entity's scalar
  actual primary key.
- Candidate reflections are grouped by target entity. The canonical inverse is
  selected by `has_one`, then `has_many`, then lexical association name. A
  candidate target appears once even when aliases or mixed macros repeat it;
  matching duplicates are not warnings.
- Different interfaces are unrelated. A same-interface reflection whose child
  or columns conflict emits `ASSOCIATION_POLYMORPHIC_OMITTED`; valid candidates
  still publish.
- After filtering, zero candidates emits exactly one
  `ASSOCIATION_POLYMORPHIC_TARGETS_UNRESOLVED` warning for the root.

### Relationship identity and projection

- Internal group key is
  `polymorphic|<holder_entity>|<interface>|<id_column>|<type_column>`.
- One public relationship is emitted per candidate target with ID:
  `relationships/<holder_table>/polymorphic/<interface>/<id_column>/<type_column>/<target_table>`.
- Public orientation is holder to concrete target. Direct and through key spaces
  never deduplicate with polymorphic relationships.
- The public label is the sanitized polymorphic root association name. Root
  declaration identity is stable because one owner model has one reflection per
  name.
- `Relationship` gains internal `foreign_type_column`; public relationship
  schemas stay unchanged.
- `IrBuilder` projects both `foreign_key_column` and `foreign_type_column` as
  `foreign_key` attributes, with normal unique sorting.

### Cardinality

- Target endpoint is always conservative `0..1`; nullability does not prove a
  concrete polymorphic target FK.
- For each emitted candidate edge, holder endpoint is `0..1` when that
  candidate inverse is `has_one` or a total plain unique index covers exactly
  the unordered `(type_column, id_column)` pair.
- Otherwise that candidate edge's holder endpoint is `0..many`. A `has_one`
  candidate never strengthen another candidate's `has_many` edge.

### Deferred shapes

- Scoped polymorphic declarations remain scoped omissions.
- Through polymorphism and `source_type:` remain P2-05 omissions.
- STI candidate expansion remains P2-02. P1-06 uses selected renderable entities
  only and does not inspect discriminator values.
- Delegated types, custom/composite keys, and polymorphic `class_name` guessing
  remain outside P1-06.

## Diagnostics

- Add one closed warning code:
  `ASSOCIATION_POLYMORPHIC_TARGETS_UNRESOLVED`.
- It uses the existing association metadata shape and relationship-build phase.
- Reuse:
  - `ASSOCIATION_KEY_COLUMN_MISSING` for absent id/type holder columns;
  - `ASSOCIATION_SCOPED_OMITTED` for root/candidate scopes;
  - `ASSOCIATION_COMPOSITE_KEY_OMITTED` and
    `ASSOCIATION_NON_PRIMARY_KEY_OMITTED` for unsupported keys;
  - `ASSOCIATION_POLYMORPHIC_OMITTED` for unmatched/conflicting/deferred
    inverse polymorphic declarations.
- Every deferred reflection yields at most one warning. A valid group root does
  not retain the former generic polymorphic warning.

## Exact Rails matrix oracle

- Add `Comment belongs_to :commentable, polymorphic: true`.
- Add `Post has_many :comments, as: :commentable` and
  `Image has_one :comment, as: :commentable`.
- Add `comments.commentable_id` and `comments.commentable_type`, plus selected
  `Comment` and `Image` entities.
- Extend the exact edge oracle with both target-specific IDs/endpoints.
- Add `rails_mmd_expected_polymorphic_groups.json`. The validator derives each
  public group ID by removing the final target-table segment and compares:
  - `group_id`;
  - holder safe token;
  - root label;
  - sorted unique candidate target safe tokens;
  - the id/type holder attributes named by the group ID, both with role
    `foreign_key`.
- This proves complete candidate membership, no duplicates, and both key
  columns; the edge oracle remains authoritative for per-target label and
  cardinality while the group label asserts the shared root.

## Public TDD seams

- `RelationshipBuilder#build` result relationships/diagnostics.
- `IrBuilder#build` entity key attributes.
- Diagnostic schema/catalog fixtures.
- Rails matrix `ArtifactValidator` exact edge/group projections.
- No private method is asserted directly.

## TDD slices

1. Red: direct polymorphic root/inverses still emit generic omissions. Green:
   two-pass inventory emits one target-specific edge per matching candidate.
2. Red: duplicate/order variants change output. Green: group and candidate keys
   sort/deduplicate independently of enumeration, including reverse-order
   `has_one`/`has_many` aliases for one target.
3. Red: type column is absent from key attributes. Green: IR projects both id
   and type columns.
4. Red: zero candidates and missing columns are generic/silent. Green: closed
   deterministic diagnostics.
5. Red: one conflicting inverse suppresses valid candidates or disappears.
   Green: valid candidates publish while each conflicting same-interface inverse
   yields one polymorphic omission warning.
6. Red: real Rails fixture lacks polymorphic proof. Green: exact edge and group
   oracles pass all three pairs.

## Planned changes

| Path | Purpose |
|---|---|
| `lib/rails_mmd/relationship_builder.rb` | Two-pass polymorphic grouping, candidate edges, diagnostics |
| `lib/rails_mmd/ir_builder.rb` | Project id and type columns as key attributes |
| `schemas/diagnostics.schema.json` | Add one closed warning code |
| `fixtures/schemas/diagnostics/**` | Valid and malformed diagnostic fixtures |
| `spec/rails_mmd/relationship_builder_spec.rb` | Public group/candidate/failure behavior |
| `spec/rails_mmd/ir_builder_spec.rb` | Two-column key projection |
| `tooling/rails_matrix.rb` | Exact polymorphic group validation |
| `fixtures/rails_matrix/template/**` | Real root/inverses/schema/exact expectations |
| `docs/p0-contract.md` | P1-06 identity, eligibility, cardinality, warning |
| `docs/active-record-association-support.md` | P1-06 status and P1-07 next work |

## Acceptance criteria

- Matching direct polymorphic roots/inverses render one edge per selected target.
- IDs, labels, endpoints, cardinalities, and candidate sets are deterministic.
- Both holder key columns are visible as FK attributes.
- Root/inverse duplicates never duplicate a target edge.
- Invalid/deferred shapes produce schema-valid warnings and no partial group.
- Ordinary direct/through output remains unchanged.
- Exact edges/groups, default Rake, pre-commit, and pre-push pass on the three
  supported Rails/Ruby pairs.

## Design review record

| Round | Perspective | Findings | Correction |
|---|---|---|---|
| 1 | Rails runtime | Mixed singular/plural candidates had contradictory group-wide cardinality | Made holder cardinality candidate-edge-specific |
| 1 | Architecture | Same cardinality inconsistency | Applied the per-edge rule and order-independent exact composite uniqueness |
| 1 | QA / TDD | Partial-success warning lacked a slice; group label proof was implicit | Added an independent conflict slice and root label to the group oracle |
| 2 | Rails runtime | None | — |
| 2 | Architecture | Same-target mixed-macro canonical inverse was undefined | Fixed `has_one`, `has_many`, lexical-name priority and silent matching-alias dedupe |
| 2 | QA / TDD | None | — |
| 3 | Architecture | None | — |
