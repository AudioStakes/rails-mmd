# P1-02 Association Detection Research

Status: research complete; reviewed with no remaining findings

## Target

Inventory every Rails 7.2/8.1 association reflection and emit a warning when a
macro is not rendered. P1-02 changes detection and diagnostics only; rendering
remains assigned to P1-03–P1-07.

## Rails facts

- `reflect_on_all_associations` without a macro returns every association
  reflection; passing a macro filters the same collection.
- The four association macros are `belongs_to`, `has_one`, `has_many`, and
  `has_and_belongs_to_many`.
- Reflection `name`, `macro`, `scope`, `has_scope?`, `polymorphic?`, and
  `through_reflection?` expose the classification needed by later P1 work.
- Exact local probes through the P1-01 locked Rails 7.2.3.1 and 8.1.3 bundles
  confirmed the same `reflect_on_all_associations` source surface.
- Rails normalizes internal reflections to their parent, so HABTM is exposed as
  one top-level HABTM reflection rather than a duplicate generated `has_many`.
- `polymorphic?` identifies the polymorphic `belongs_to`; inverse `as:`
  associations require separate option/type inspection. `has_scope?` is broader
  than `scope` for through/source chains.

Reproduce the version and method surface after the P1-01 matrix cache is ready:

```sh
for series in 7.2 8.1; do
  ASDF_RUBY_VERSION=4.0.6 \
    BUNDLE_GEMFILE="$PWD/fixtures/rails_matrix/bundles/$series/Gemfile" \
    BUNDLE_PATH="$PWD/.bundle/rails-matrix/gems/4.0.6" \
    asdf exec bundle exec ruby -e \
      'require "active_record"; puts ActiveRecord.version; p ActiveRecord::Base.method(:reflect_on_all_associations).source_location'
done
```

## Repository facts

- `RelationshipBuilder` requests only
  `reflect_on_all_associations(:belongs_to)`; its fallback filters
  `reflections.values` to the same macro.
- `has_one`, `has_many`, and HABTM are therefore silently omitted. Existing
  tests require this silence.
- Eligible `belongs_to` records are rendered. Ineligible `belongs_to` records
  already emit schema-backed `relationship_build` warnings.
- Diagnostic codes, catalog entries, metadata shapes, and contract fixtures are
  closed sets. A new warning must update all of them together.
- The shared association metadata already identifies domain, owner, association,
  and optional target. It does not identify the macro.
- The support matrix assigns rendering to P1-03–P1-07 and describes P1-02 as
  reflection classification plus omission diagnostics.
- Current test doubles intentionally reject
  `reflect_on_all_associations` without `:belongs_to`; broad inventory will make
  this stale harness assumption fail before product behavior is exercised.
- Successful relationships are sorted by ID, but diagnostics retain reflection
  iteration order. Existing specs assert that order, while the Rails API does
  not document it as a compatibility guarantee.

## Contract tension

The P0 contract intentionally says non-`belongs_to` associations are omitted
without warnings. If P1-02 changes that contract for Rails 7.2/8.1, the
executable diagnostic schema/catalog and support matrix need an aligned,
explicit update. The P0 eligibility and rendering rules are otherwise separate.

## Risks and design inputs

- Calling `klass`, key methods, or through resolution while inventorying can
  raise and accidentally make warning-only omissions fatal.
- One generic code needs structured macro metadata; macro-specific codes avoid
  that schema field but multiply public codes and become awkward as later PRs
  support only direct subsets.
- Reflection enumeration has no documented ordering contract. Design must choose
  a stable diagnostic order rather than inheriting incidental reflection order,
  and produce one warning per omitted association without duplicating existing
  `belongs_to` warnings.
- The reflections fallback is needed by isolated tests and nonstandard model
  doubles even though Rails 7.2/8.1 provide the primary API.

## Research review record

| Round | Perspective | Findings | Correction |
|---|---|---|---|
| 1 | Rails runtime | Exact-version probe provenance and the unrelated Rails 8.1 deprecation claim were weak | Added the locked-bundle reproduction command and removed the unrelated claim |
| 1 | contract | Rendering ownership was uncited and P1-02 was described as already superseding P0 | Cited the support matrix and made contract change conditional |
| 1 | QA | Reflection-order oracle and stale `:belongs_to`-only doubles were absent | Recorded the undocumented order and the immediate harness failure boundary |
| 2 | contract | None | No change |
| 2 | QA | None | No change |
| 3 | Rails runtime | None | No change |

## Sources

- [Rails 7.2.3.1 Reflection API](https://api.rubyonrails.org/v7.2.3.1/classes/ActiveRecord/Reflection/ClassMethods.html)
- [Rails 7.2 association macros](https://api.rubyonrails.org/v7.2/classes/ActiveRecord/Associations/ClassMethods.html)
- [Rails 8.1.3 Reflection source](https://raw.githubusercontent.com/rails/rails/v8.1.3/activerecord/lib/active_record/reflection.rb)
- [Rails 8.1 association macros](https://api.rubyonrails.org/v8.1/classes/ActiveRecord/Associations/ClassMethods.html)
- `activerecord-7.2.3.1/lib/active_record/reflection.rb`
- `activerecord-8.1.3/lib/active_record/reflection.rb`
- `lib/rails_mmd/relationship_builder.rb`
- `schemas/diagnostics.schema.json`
- `fixtures/schemas/diagnostics/valid/catalog.json`
- `docs/p0-contract.md`
- `docs/active-record-association-support.md`
