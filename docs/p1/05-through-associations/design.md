# P1-05 Through Associations Design

Status: design complete; reviewed with no remaining findings

## Decisions

### Eligibility and path resolution

- Classify `through_reflection?` before the direct has path.
- Support `has_many :through` and `has_one :through` with a Rails-inferred,
  non-polymorphic source and no effective scope or `source_type`.
- An explicit `source:`/`source_type:`, polymorphic through/source, or scoped
  chain remains a generic/specific omission for its later owner.
- Resolve `through_reflection`, `source_reflection`, and the full
  `collect_join_chain` without executing scopes. Rails returns that chain from
  the outer declaration back toward the owner; reverse it exactly once, then
  replace the outer declaration hop with the terminal source-reflection name.
  For nested `Author -> posts -> taggings -> tag`, native names
  `tags, taggings, posts` normalize to `posts/taggings/tag`.
- The normalized path includes every resolved reflection from the owner-side
  first hop through the final target source reflection. Nested through is valid
  only when every hop resolves, is unscoped/non-polymorphic, and every hop model
  is renderable and selected in the same domain.
- Every intermediate and final model must resolve, be renderable, and be a
  selected same-domain entity. No hidden/out-of-domain join model is invented.

### Relationship model

- Preserve every P1-04 direct physical edge. A through semantic edge is a
  separate internal relationship kind and is never grouped into a direct FK
  key.
- Canonical through identity is owner entity + normalized full path + final
  target entity. Public ID is
  `relationships/<owner_table>/through/<path...>/<target_table>`.
- Same path duplicates collapse to one edge. Label winner priority is
  `has_one`, `has_many`, then lexical declaration ID. Distinct paths to the same
  final target remain distinct.
- Public orientation follows the declaration owner -> final target. Owner
  cardinality is conservatively `0..many`; target cardinality is `0..many` for
  has-many-through and the Active Record bound `0..1` for has-one-through.
- Through semantic edges carry no FK-holder column and therefore add no FK
  attribute. Existing direct edges retain all key projection.
- Public IR/render-plan schemas remain unchanged; normalized path provenance is
  encoded in the public ID and retained internally as relationship kind/key.

### Diagnostics

- Add `ASSOCIATION_THROUGH_UNRESOLVED` for missing/invalid intermediate
  reflection or model resolution.
- Add `ASSOCIATION_SOURCE_UNRESOLVED` for missing/ambiguous source, a nested
  chain that cannot collect/resolve every hop, or final source model resolution.
  A fully resolved nested chain that fails scope/polymorphic/domain eligibility
  uses that specific later diagnostic instead.
- Both are warning, relationship-build, relationship-scope diagnostics using
  the existing closed association metadata shape.
- Reuse `ASSOCIATION_TARGET_NOT_RENDERABLE_OMITTED` and
  `DOMAIN_RELATIONSHIP_OMITTED` after a model resolves but fails renderability or
  selected-domain membership.
- Explicit `source:` remains `ASSOCIATION_MACRO_OMITTED`; `source_type` or
  polymorphic paths use `ASSOCIATION_POLYMORPHIC_OMITTED`; effective scopes use
  `ASSOCIATION_SCOPED_OMITTED`.

### Real-Rails acceptance

- Extend the shared app with one-hop has-many-through, has-one-through, and
  nested has-many-through paths whose intermediate/final models are selected,
  plus two distinct paths to the same target.
- Exact relationship projection proves direct intermediate edges coexist with
  one semantic edge per normalized path on all three Rails/Ruby pairs.
- Unit/contract fixtures cover same-path dedupe, distinct paths, missing or
  ambiguous through/source, scoped/polymorphic/explicit-source omissions, and
  closed diagnostic schemas.
- Rails stores one reflection per owner association name, so two identical
  supported declarations cannot coexist in one real model. Same-path duplicate
  grouping is therefore a synthetic builder regression; the real matrix proves
  distinct paths remain distinct and exact across versions.

## Public TDD seams

1. `RelationshipBuilder#build` returns direct physical plus canonical through
   semantic edges and warning-only failures.
2. Diagnostic schema/catalog accepts the two new closed codes and rejects
   malformed metadata.
3. `verify:rails_matrix` rejects absent, duplicate, or path-incorrect public
   relationships across Rails 7.2.3.1 and 8.1.3.

## TDD slices

1. Red: simple through remains `ASSOCIATION_MACRO_OMITTED`. Green: resolve the
   inferred one-hop chain and emit one semantic edge.
2. Red: has-one-through uses collection cardinality. Green: macro-specific
   target bound.
3. Red: nested paths flatten/collide. Green: full reversed join-chain identity.
4. Red: same-path aliases duplicate and distinct paths collide. Green:
   path-key grouping plus deterministic winner.
5. Red: missing through/source is generic or fatal. Green: closed warning codes
   with negative schema fixtures.
6. Red: the real matrix passes without through edges. Green: exact one-hop,
   singular, and nested relationship projections for all three pairs.

## Planned changes

| Path | Purpose |
|---|---|
| `lib/rails_mmd/relationship_builder.rb` | Resolve, validate, group, and build through paths |
| `schemas/diagnostics.schema.json` | Add two closed warning codes |
| `fixtures/schemas/diagnostics/**` | Valid catalog plus malformed metadata cases |
| `spec/rails_mmd/relationship_builder_spec.rb` | Public simple/nested/dedupe/failure behavior |
| `spec/contracts/schema_spec.rb` | Closed diagnostic metadata |
| `fixtures/rails_matrix/template/**` | Real through paths and exact expectations |
| `docs/p0-contract.md` | P1-05 path identity, cardinality, and warnings |
| `docs/active-record-association-support.md` | P1-05 status and P1-06 next work |

## Acceptance criteria

- Inferred-source has-many/has-one-through and nested through render on Rails
  7.2.3.1 and 8.1.3 with selected intermediate and final models.
- Direct physical edges remain; same normalized semantic path appears once and
  distinct paths remain distinct.
- Unsupported option/polymorphic/scope and invalid resolution paths are
  deterministic schema-valid warnings, never fatal.
- Exact relationship/diagnostic projections, default Rake, pre-commit, and
  pre-push pass.

## Design review record

| Round | Perspective | Findings | Correction |
|---|---|---|---|
| 1 | Rails runtime | Chain orientation was ambiguous | Fixed native outer-to-owner order and one reverse with a concrete nested path |
| 1 | Architecture | Full owner-to-final path scope was not closed | Defined every resolved hop through the final source reflection |
| 1 | QA / TDD | Valid nested boundary and real same/distinct-path evidence were unclear | Fixed per-hop eligibility and separated synthetic dedupe from real distinct-path parity |
| 2 | Rails runtime | None | — |
| 2 | Architecture | None | — |
| 2 | QA / TDD | None | — |
