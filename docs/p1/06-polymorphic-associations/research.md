# P1-06 Polymorphic Associations Research

Status: research complete and reviewed

## Target

Render direct polymorphic associations on Rails 7.2/8.1 with both discriminator
columns and deterministic, duplicate-free selected-domain target candidates.

## Rails facts

- A polymorphic `belongs_to` exposes `polymorphic?`, `foreign_key`, and
  `foreign_type`, but has no single concrete `klass`; reading `klass` can raise
  `ArgumentError`.
- An inverse `has_many`/`has_one ..., as: :interface` is not itself
  `polymorphic?`. Its `options[:as]`, `foreign_key`, `type`, and fixed child
  `klass` identify the polymorphic interface and holder table.
- Automatic inverse discovery is asymmetric. A polymorphic `belongs_to` does
  not provide the complete candidate set, while inverse `as:` declarations can
  identify concrete owner candidates.
- The physical key is the pair of scalar `<interface>_type` and
  `<interface>_id` columns. A normal database FK usually cannot prove a
  concrete target for that pair.
- Rails stores the base polymorphic name for STI families. Candidate expansion
  or subtype display therefore requires the separate P2-02 STI policy.
- Rails 7.2.3.1 and 8.1.3 probes showed no relevant reflection API difference.

## Repository facts

- `RelationshipBuilder` currently omits both polymorphic `belongs_to` and
  inverse `as:` declarations with `ASSOCIATION_POLYMORPHIC_OMITTED`.
- Relationship IR/render-plan schemas require one `target_entity_id`; they have
  no candidate-array field. Mermaid also requires concrete endpoints.
- The existing builder iterates selected same-domain entities and can therefore
  match an actual polymorphic `belongs_to` root with selected inverse `as:`
  candidates without global model guessing.
- P1-04 direct keys and P1-05 through keys are separate identity spaces. A
  polymorphic group needs holder, id column, type column, and target dimensions.
- `IrBuilder` currently marks one FK column per relationship. P1-06 must project
  both id and type columns as key attributes without changing the public
  attribute schema.
- The exact Rails matrix oracle can prove target-specific IDs, endpoints,
  labels, cardinalities, and duplicate suppression on all three supported
  Rails/Ruby pairs.

## Minimum P1-06 scope

- Support direct, unscoped polymorphic `belongs_to` roots.
- Discover candidates only from direct, unscoped `has_many`/`has_one` inverse
  reflections with matching `as:`, child model, scalar foreign key, and scalar
  type column.
- Require root and candidate entities to be selected in the same domain.
- Require the holder's id and type columns to exist and the target to use its
  scalar actual primary key.
- Build one internal semantic group and one public edge per concrete candidate.
- Keep public schemas unchanged. Candidate membership is visible through the
  target-specific edge set.
- Project both holder columns as `foreign_key` attributes when key attributes
  are requested.
- Keep scoped polymorphic associations, through polymorphism, `source_type:`,
  custom/composite keys, delegated types, and STI expansion out of scope.

## Candidate and identity boundaries

- A polymorphic root is mandatory. An inverse `as:` declaration alone does not
  invent a group.
- Candidate matching requires the same interface name, child holder entity,
  foreign-key column, and foreign-type column.
- Internal group key:
  `<holder_entity>|<id_column>|<type_column>|<interface>`.
- Public edge ID:
  `relationships/<holder_table>/polymorphic/<interface>/<id_column>/<type_column>/<target_table>`.
- The interface segment prevents same-column polymorphic aliases from colliding
  and keeps internal/public group identity aligned.
- Direct, through, and polymorphic relationships never deduplicate across key
  spaces.
- Candidate and reflection order must not change IDs, labels, or edge count.
- Label priority is polymorphic `belongs_to`, inverse `has_one`, inverse
  `has_many`, then lexical association name.

## Cardinality boundaries

- Canonical orientation is polymorphic holder to concrete candidate target.
- Holder endpoint is `0..1` when a matching inverse `has_one` exists or a total
  plain unique index covers the `(type, id)` pair; otherwise `0..many`.
- Target endpoint is conservatively `0..1`. Column nullability alone does not
  prove a concrete target database FK.

## Failure boundaries

- Missing id or type column omits the whole group; it must not publish a partial
  key.
- Candidate matching is strict. Inverse reflections with a different interface,
  child holder, id column, or type column are not members of the group.
- After strict filtering, zero candidates emits one warning and no edge.
- When valid and mismatching inverse reflections coexist, valid candidates are
  published; each structurally conflicting same-interface inverse remains on
  `ASSOCIATION_POLYMORPHIC_OMITTED`. Unrelated interfaces are silently evaluated
  only for their own root groups.
- Unsafe names, scopes, custom/composite keys, and deferred polymorphic-through
  shapes keep deterministic omission paths.
- Candidate discovery is selected-domain only. P1-06 does not scan or publish
  out-of-domain model names.
- `ASSOCIATION_POLYMORPHIC_OMITTED` remains for deferred or conflicting inverse
  shapes. Add `ASSOCIATION_POLYMORPHIC_TARGETS_UNRESOLVED` for a structurally
  valid root with zero candidates. Reuse `ASSOCIATION_KEY_COLUMN_MISSING` when
  either holder id or type column is absent.

## Required test boundaries

- one polymorphic root with `has_many as:` and `has_one as:` candidates;
- paired root/inverse declarations collapse to one edge per candidate;
- both type and id columns become key attributes;
- inverse and model enumeration order invariance;
- duplicate inverse declarations for one candidate;
- exact group projections containing group ID plus the sorted, unique complete
  candidate target-token set, in addition to existing target-specific edge
  projections;
- zero candidates and missing id/type columns;
- scoped, through/source-type, composite/custom-key, and unsafe-name omissions;
- real Rails exact edges on all three supported pairs.

## Research review record

| Round | Perspective | Findings | Correction |
|---|---|---|---|
| 1 | Rails runtime | None | — |
| 1 | Architecture | Internal interface dimension was absent from public IDs | Added the interface segment to every polymorphic edge ID |
| 1 | QA / TDD | Group completeness, mismatch filtering, and diagnostics were open | Fixed strict filtering, partial-success rules, exact group oracle, and warning codes |
| 2 | Rails runtime | None | — |
| 2 | Architecture | None | — |
| 2 | QA / TDD | None | — |

## Sources

- Rails Association Basics, Polymorphic Associations:
  <https://guides.rubyonrails.org/association_basics.html#polymorphic-associations>
- Rails 8.1 `ActiveRecord::Associations::ClassMethods` polymorphic API:
  <https://api.rubyonrails.org/v8.1.3/classes/ActiveRecord/Associations/ClassMethods.html#label-Polymorphic+Associations>
- Rails 8.1 `source_type` API:
  <https://api.rubyonrails.org/v8.1.3/classes/ActiveRecord/Associations/ClassMethods.html#label-3Asource_type>
