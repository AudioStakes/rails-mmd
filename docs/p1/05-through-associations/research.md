# P1-05 Through Associations Research

Status: research complete; reviewed with no remaining findings

## Target

Render `has_many :through` and `has_one :through` on Rails 7.2.3.1 and
8.1.3 while retaining the selected intermediate model and its direct physical
edges. Explicit `source`, `source_type`, polymorphic paths, and non-primary-key
options remain assigned to P2-05/P1-06 by the support matrix.

## Rails facts

- A through declaration is an `ActiveRecord::Reflection::ThroughReflection`;
  `through_reflection?` is true on Rails 7.2.3.1 and 8.1.3.
- `through_reflection` resolves the owner-side intermediate association.
  `source_reflection` resolves the association on that intermediate model;
  explicit `source:` wins, otherwise Rails derives singular/plural candidates.
  Rails supports that option, but rails-mmd intentionally omits it in P1-05.
- `source_reflection_name` can be ambiguous. Missing through/source reflections,
  invalid declaration order, and incompatible source types raise Rails
  association errors rather than returning a usable path.
- `nested?` identifies a through or source reflection that is itself through;
  `collect_join_chain` exposes the normalized multi-hop chain.
- Some through key methods delegate to the source reflection (`foreign_key`,
  `foreign_type`, and `join_foreign_key`), while
  `association_primary_key`/`join_primary_key` are overridden and may consult
  the actual source reflection. The direct FK tuple reader is not a safe path
  model.
- `has_scope?` is true for a through declaration scope, source/through scopes,
  or `source_type`. Scope execution is not required to identify the structural
  chain.
- A polymorphic source requires `source_type`; a non-polymorphic source rejects
  it. Those typed paths need a type dimension and stay outside P1-05.
- A polymorphic `through_reflection` is separately invalid for both has-one and
  has-many through declarations; it is not the same as a polymorphic source.
- A `has_one :through` cannot traverse a collection through association. Rails
  validates this independently of target resolution.

## Repository facts

- P1-02 inventories through declarations, but P1-03 classifies them before
  direct processing and emits `ASSOCIATION_MACRO_OMITTED`.
- P1-04 direct identity is one physical FK tuple. A through declaration is a
  path-derived semantic relation and cannot share that key space.
- Selected intermediate models already appear as entities. Their direct
  associations already produce canonical physical edges, so P1-05 must retain
  those edges and add at most one owner-to-final-target semantic edge per
  normalized through path.
- Public IR/render-plan relationship fields can carry a through semantic edge
  without schema expansion. Path provenance may remain internal if its
  canonical public ID includes the normalized intermediate/source path.
- The exact Rails matrix relationship oracle compares ID, endpoints, label, and
  cardinalities, and can prove that direct and semantic edges coexist without
  duplicates on all three supported pairs.
- The support matrix assigns `source`, `source_type`, `as`, and custom key
  options to P2-05, while P1-05 owns the base through macros.

## Contract tensions and risks

- “Render the intermediate model and destination” requires two layers: direct
  physical edges keep the intermediate model connected, while a distinct
  semantic edge represents the declared through association.
- A through public ID must include the owner, normalized path, and final target,
  but not the declaration name. Final endpoints alone collide when two paths
  reach the same target; declaration names prevent same-path deduplication.
- The normalized path is the ordered full chain of resolved reflection names,
  beginning with the owner-side through reflection and continuing through the
  resolved source/nested chain, ending in the terminal source-reflection name
  rather than the outer declaration name. Raw options and declaration order are
  not part of identity.
- Direct-vs-through edges are not duplicates: one represents physical schema,
  the other Active Record reachability. Duplicate suppression applies only
  within the same normalized through path.
- Nested through must either normalize the full chain or emit an explicit
  omission; silently flattening only the first hop produces a false path.
- Intermediate and final models must both resolve, be renderable, and be
  selected in the same domain. Missing intermediate and missing source/target
  failures need distinguishable diagnostics.
- P1-05 accepts only Rails-inferred sources. An explicit `source:` or any
  `source_type:` is detected and omitted for P2-05; it is never partially
  resolved as a base through path.
- Missing/invalid through resolution uses `ASSOCIATION_THROUGH_UNRESOLVED`;
  missing or ambiguous source/final resolution uses
  `ASSOCIATION_SOURCE_UNRESOLVED`. Both are warning paths.
- Through cardinality is semantic rather than DB-enforced. The final target
  endpoint is `0..many` for `has_many :through` and `0..1` for
  `has_one :through`; the owner endpoint remains conservatively `0..many`.

## Required test boundaries

- simple inferred-source `has_many :through` and `has_one :through`;
- nested through full-chain normalization;
- same final target through two distinct paths;
- duplicate declarations of the same normalized path;
- missing/ambiguous through or source reflection;
- unresolved, non-renderable, or out-of-domain intermediate/final model;
- scoped and polymorphic/source-type paths remain deterministic omissions;
- exact identical projections on Rails 7.2.3.1 and 8.1.3.
- the exact matrix projection compares the path-bearing public relationship ID,
  endpoints, label, and cardinalities for distinct-path and same-path cases.

## Research review record

| Round | Perspective | Findings | Correction |
|---|---|---|---|
| 1 | Rails runtime | Key delegation was overbroad; polymorphic-through invalidity was missing | Named delegated/overridden methods and separated through-vs-source polymorphism |
| 1 | Architecture | Public ID conflicted with path dedupe; normalized path was undefined | Removed declaration name and defined the full resolved reflection chain |
| 1 | QA / contract | Source scope, exact path oracle, and failure diagnostics were ambiguous | Limited P1-05 to inferred source and fixed IDs plus through/source warning codes |
| 2 | Rails runtime | None | — |
| 2 | Architecture | None | — |
| 2 | QA / contract | None | — |

## Sources

- [Rails 7.2.3.1 reflection source](https://raw.githubusercontent.com/rails/rails/v7.2.3.1/activerecord/lib/active_record/reflection.rb)
- [Rails 8.1.3 reflection source](https://raw.githubusercontent.com/rails/rails/v8.1.3/activerecord/lib/active_record/reflection.rb)
- `lib/rails_mmd/relationship_builder.rb`
- `docs/active-record-association-support.md`
- `docs/p1/04-inverse-canonical-edges/design.md`
