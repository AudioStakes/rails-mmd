# P1-04 Inverse Canonical Edges Design

Status: design complete; reviewed with no remaining findings

## Decisions

- Group every supported direct candidate by P1-03 physical identity: FK holder
  entity/column plus referenced entity/primary key. Inverse metadata is
  supporting evidence and never the sole identity.
- Publish exactly one relationship per group. A supported direct declaration
  with `inverse_of: false` still participates: a one-candidate group publishes
  it unchanged in count, while a multi-candidate group canonicalizes regardless
  of inverse metadata. The same rule covers explicit/automatic inverse, aliases,
  and self joins.
- Canonical orientation is FK holder -> referenced entity.
- Canonical public ID is
  `relationships/<holder_table>/<fk_column>/<referenced_table>/<primary_key>`.
- Label winner priority is `belongs_to`, `has_one`, `has_many`, then lexical
  declaration relationship ID. The winner supplies only the label/macro; it
  does not control ID, orientation, or cardinality.
- Canonical holder cardinality is `0..1` when any eligible candidate in the
  group is `has_one`, regardless of label winner, or when a total plain unique
  FK index exists; otherwise it is `0..many`. Referenced cardinality is
  `1..1` only with DB FK plus non-null FK, otherwise `0..1`.
- Preserve actual FK-holder projection in IR. No public schema or diagnostic
  code changes are required.
- Update the P0 extension contract and matrix expected relationships for the
  canonical ID/orientation. Add explicit, automatic, false, alias, and paired
  self-join cases; keep inverse-free direct edges.

## Public TDD seams

1. `RelationshipBuilder#build` emits one declaration-independent canonical
   edge per physical group with stable ID, orientation, label, and cardinality.
2. Exact real matrix relationship projections stay identical across all three
   Rails/Ruby pairs and reject declaration/inverse-option churn.
3. `IrBuilder` still marks the canonical holder FK and serializes no internal
   inverse/canonical fields.

## TDD slices

1. Red: paired direct/`belongs_to` keeps a declaration ID. Green: canonical
   physical ID and orientation.
2. Red: aliases and multiple same-macro declarations depend on enumeration.
   Green: fixed macro/lexical label tie-break.
3. Red: explicit, automatic, false, and self inverse variants differ in count
   or output. Green: identical physical canonicalization.
4. Red: matrix expected relationship IDs/orientations mismatch. Green: exact
   canonical projections on Rails 7.2.3.1 and 8.1.3.
5. Regression: an inverse-free one-candidate direct edge keeps one edge and is
   canonicalized only in ID/orientation, never merged with another physical key.

## Acceptance criteria

- One physical direct link yields one edge regardless of inverse declaration.
- `inverse_of: false` suppresses Rails inverse metadata only; it never prevents
  same-physical-key grouping. A one-candidate group remains one edge.
- Public ID and orientation do not change with declaration order or winner.
- Label tie-break and physical cardinalities are deterministic.
- Direct-only and self-join groups remain valid; through, polymorphic, and
  HABTM remain excluded.
- Default Rake, 3-pair matrix, pre-commit, and pre-push pass.

## Design review record

| Round | Perspective | Findings | Correction |
|---|---|---|---|
| 1 | Rails runtime | None | — |
| 1 | Architecture | `inverse_of: false` single/multi-candidate boundary was coarse | Defined participation and count for both group sizes |
| 1 | QA / TDD | False-inverse causality, has-one conflicts, and one-candidate regression were unclear | Fixed physical grouping, any-has-one semantics, and regression slice |
| 2 | Architecture | None | — |
| 2 | QA / TDD | None | — |
