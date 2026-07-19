# P1-03 Direct Has Associations Design

Status: design complete; reviewed with no remaining findings

## Decisions

### Eligibility and classification

- Keep the existing `belongs_to` path unchanged.
- A direct has candidate has macro `has_many` or `has_one`, no through
  reflection, no scope, and no polymorphic-owner type.
- Classify through before scope and classify owner-side `as:` by non-nil
  reflection `type`; unsupported forms remain omission diagnostics.
- Reuse the existing name, target resolution/renderability, same-domain,
  scalar-key, primary-key, and column-existence guardrails.
- Direct keys are target `foreign_key` -> declaring owner
  `active_record_primary_key`. The owner key must equal the probed entity's
  actual primary key.

### Internal relationship normalization

- Keep public IR/render-plan schemas unchanged.
- Canonicalize every direct candidate to FK-holder -> referenced orientation
  before it leaves `RelationshipBuilder`. The published relationship therefore
  already carries the actual FK-holding entity in `owner_entity_id`, the
  referenced entity in `target_entity_id`, the stable public relationship ID,
  and any public FK columns.
- Rich normalization evidence stays private to `RelationshipBuilder`
  candidates: referenced primary key, declaration owner, inverse/declaration
  macro, FK nullability/uniqueness, and DB-FK evidence.
- `IrBuilder` marks the FK attribute on the published `owner_entity_id`.
- Physical identity is the tuple FK-holder entity/column plus referenced
  entity/primary key. If a `belongs_to` candidate has the same tuple, it wins so
  P0 IDs and labels remain stable. P1-04 owns inverse-aware reconciliation;
  P1-03 does not call `inverse_of`.
- Therefore P1-03 does not make every direct declaration independently visible:
  when `belongs_to` already represents the physical link, the direct has adds
  neither an edge nor a warning. Inverse-free direct has declarations remain
  independently visible.
- Public key attributes are emitted on the actual FK-holding entity, which is
  not necessarily the relationship declaration owner. Record this P1-03
  projection rule in `docs/p0-contract.md`; the closed IR schema itself does not
  change.

### Cardinality

- Direct `has_many`, declaration orientation `Owner -> Target`:
  owner endpoint is `1..1` only with DB FK plus non-null target FK, otherwise
  `0..1`; target endpoint is `0..many`.
- Direct `has_one`: the owner endpoint follows the same FK evidence and the
  target endpoint is the Active Record semantic bound `0..1`.
- Target-FK uniqueness is retained as internal evidence but is not required to
  render `has_one`. The real fixture uses a unique index so AR and DB semantics
  agree.
- Self joins use the same endpoint rules. `Employee.has_many :reports` with a
  nullable `manager_id` yields one loop labeled `reports`, `0..1` at owner and
  `0..many` at target.

### Diagnostics

- Eligible direct `has_many` / `has_one` no longer emit
  `ASSOCIATION_MACRO_OMITTED`.
- Through remains `ASSOCIATION_MACRO_OMITTED` until P1-05.
- Scoped direct has uses `ASSOCIATION_SCOPED_OMITTED`; owner-side polymorphic
  `as:` uses `ASSOCIATION_POLYMORPHIC_OMITTED`.
- Other failures reuse existing target, domain, composite/non-primary key,
  missing-column, and unsafe-name codes with the declaring owner in metadata.
- Target-resolution exceptions use `ASSOCIATION_TARGET_UNRESOLVED`; direct key
  reader exceptions use `ASSOCIATION_COMPOSITE_KEY_OMITTED`. Neither becomes
  fatal.

### Real-Rails acceptance

- Extend the matrix app with `Profile` (no inverse declaration), a has-many-only
  target, and `Employee.has_many :reports` (no inverse declaration). Keep
  `Post.belongs_to :author` alongside `Author.has_many :posts` to prove
  provisional duplicate suppression, and keep HABTM omitted.
- Add a versioned expected-relationships JSON projection. Compare the ER render
  plan's relationship ID, owner/target safe token, label, and both
  cardinalities. Diagnostics continue using their existing structured oracle.
- Expected public edges cover existing `Post.author`, direct `Author.profile`,
  a direct has-many-only association, and the self join.

## Public TDD seams

1. `RelationshipBuilder#build` returns eligible direct has edges with correct
   endpoints, target-side FK evidence, cardinality, diagnostics, and provisional
   deduplication.
2. `IrBuilder#build` marks the FK attribute on the canonical holder-side
   published by `RelationshipBuilder`.
3. `verify:rails_matrix` rejects missing/wrong expected relationship
   projections and all three real Rails/Ruby pairs publish the exact projection.

## TDD slices

1. Red: inverse-free direct `has_many` / `has_one` produce omission warnings.
   Green: add direct classification and key projection with their has-side
   labels.
2. Red: IR marks no FK or marks it on the declaration owner. Green:
   canonicalize to the actual holder before publication and project from that
   published owner.
3. Red: through, scoped, `as:`, non-primary, unresolved, and missing-column
   cases are misclassified or fatal. Green: order guardrails and reuse omission
   codes.
4. Red: paired `Post.belongs_to :author` and `Author.has_many :posts` produce
   duplicate physical edges. Green: keep only the existing `belongs_to` edge;
   inverse-free `profile`, collection-only, and self edges retain has labels.
5. Red: the real matrix passes without direct edges. Green: compare exact
   relationship projections across the three supported pairs.

## Planned changes

| Path | Purpose |
|---|---|
| `lib/rails_mmd/relationship_builder.rb` | Direct classification, private candidate normalization, holder-oriented publication, cardinality, provisional dedupe |
| `lib/rails_mmd/ir_builder.rb` | Mark FK attributes from the published canonical holder |
| `spec/rails_mmd/relationship_builder_spec.rb` | Public direct/omission/self/dedupe behavior |
| `spec/rails_mmd/ir_builder_spec.rb` | Target-side FK projection |
| `tooling/rails_matrix.rb` | Exact real-app relationship oracle |
| `spec/integration/rails_matrix_task_spec.rb` | Reject missing relationship behavior |
| `fixtures/rails_matrix/template/**` | Real direct has, self join, keys, and expectations |
| `docs/p0-contract.md` | P1-03 eligibility, endpoint, and diagnostic extension |
| `docs/active-record-association-support.md` | Completion state and P1-04 next work |
| `docs/p1/03-direct-has-associations/implementation.md` | Red/green and review evidence |

## Acceptance criteria

- Rails 7.2.3.1 and 8.1.3 render eligible direct `has_many` and `has_one` with
  target-side FK evidence and declaration-oriented labels.
- Existing `belongs_to` output remains byte-compatible when it wins a duplicate
  physical tuple; the suppressed direct declaration adds no warning.
- Through, scoped, polymorphic-owner, non-primary, unresolved, out-of-domain,
  composite, unsafe-name, and missing-column paths remain deterministic warning
  paths.
- Direct self join emits one correctly labeled and cardinality-bearing loop.
- IR marks the published canonical holder-side FK column.
- Exact relationship and diagnostic projections pass for all three Rails matrix
  pairs; default Rake and both repository hooks pass.

## Design review record

| Round | Perspective | Findings | Correction |
|---|---|---|---|
| 1 | Rails runtime | None | — |
| 1 | Architecture | Direct visibility and FK attribute projection were ambiguous | Fixed suppression semantics and actual-FK-holder public projection |
| 1 | QA / TDD | Matrix/TDD inverse fixtures contradicted the winner rule | Limited direct-label oracles to inverse-free fixtures and isolated the paired Post case |
| 2 | Architecture | None | — |
| 2 | QA / TDD | None | — |
