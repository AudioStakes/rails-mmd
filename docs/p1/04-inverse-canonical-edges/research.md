# P1-04 Inverse Canonical Edges Research

Status: research complete; reviewed with no remaining findings

## Target

Represent one direct physical association as one declaration-independent edge
on Rails 7.2.3.1 and 8.1.3. P1-04 uses inverse metadata as supporting evidence;
through, polymorphic, and HABTM identity remain P1-05--P1-07.

## Rails facts

- `reflection.inverse_of` resolves `inverse_name` then looks up the target
  reflection. Explicit `inverse_of:` takes priority over automatic inference.
- `inverse_of: false` yields no inverse. Automatic inference is disabled or
  constrained by through, explicit `foreign_key`, scopes, and
  `inverse_of: false`. The probed self-join pair did not auto-resolve, but a
  self join is not a distinct source-level blocker by itself.
- Valid automatic inverses require matching foreign keys and compatible owner
  classes. Rails 7.2.3.1 and 8.1.3 showed the same behavior in locked-bundle
  probes.
- Simple `Author.has_many :posts` / `Post.belongs_to :author` and singular
  equivalents resolve automatically. Custom-key aliases and self joins need
  explicit inverse declarations if inverse metadata is required.
- Consequently, `inverse_of` alone is not a complete canonical identity. The
  scalar FK-holder/column and referenced entity/primary-key tuple is the stable
  identity for supported direct associations.

## Repository facts

- P1-03 groups candidates by that physical tuple but publishes the winning
  declaration's orientation and declaration-based ID.
- `belongs_to` wins a P1-03 group, preserving P0 IDs/labels. Direct-only edges
  therefore use a different orientation and ID policy from paired edges.
- Render-plan consumers need only endpoints, label, and cardinalities; the
  canonicalization can remain inside `RelationshipBuilder` without schema
  expansion.
- The exact matrix relationship oracle already exposes ID, endpoints, label,
  and cardinalities, so it will detect declaration-order or inverse-option
  instability.

## Risks and design inputs

- Canonical identity, orientation, ID, label, and cardinalities must all be
  declaration-independent; changing only deduplication leaves winner churn.
- Physical FK orientation is deterministic: FK holder -> referenced entity.
  A physical canonical ID must include holder table/column and referenced
  table/primary key to avoid collisions.
- The least disruptive label rule is `belongs_to` label when present, otherwise
  the deterministic direct-has label. Ties use macro priority (`belongs_to`,
  `has_one`, `has_many`) then lexical declaration relationship ID.
- Cardinalities must be normalized to physical orientation rather than copied
  from a declaration whose endpoints may be reversed.
- Explicit inverse, automatic inverse with no option, explicit
  `inverse_of: false`, alias, and self-join fixtures must separately
  prove that inverse metadata neither creates duplicates nor changes canonical
  identity.
- The public `relationship_id` itself is the physical canonical ID and is
  compared by the existing exact matrix projection; no separate private-ID
  oracle is needed.

## Research review record

| Round | Perspective | Findings | Correction |
|---|---|---|---|
| 1 | Rails runtime | Self joins were stated as a source-level blocker | Separated documented blockers from the observed self-join probe |
| 1 | Architecture | Alias label tie-break was missing | Added macro priority and lexical declaration-ID tie-break |
| 1 | QA | Automatic/false inverse and canonical-ID oracle were ambiguous | Split fixtures and fixed public relationship ID as the exact oracle |
| 2 | Rails runtime | None | — |
| 2 | Architecture | None | — |
| 2 | QA | None | — |

## Sources

- [Rails 7.2.3.1 reflection source](https://raw.githubusercontent.com/rails/rails/v7.2.3.1/activerecord/lib/active_record/reflection.rb)
- [Rails 8.1.3 reflection source](https://raw.githubusercontent.com/rails/rails/v8.1.3/activerecord/lib/active_record/reflection.rb)
- `lib/rails_mmd/relationship_builder.rb`
- `docs/p1/03-direct-has-associations/design.md`
- `fixtures/rails_matrix/template/rails_mmd_expected_relationships.json`
