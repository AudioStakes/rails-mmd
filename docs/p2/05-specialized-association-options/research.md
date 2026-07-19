# P2-05 Specialized Association Options Research

Status: complete

## Product boundary

P2-05 closes the option-resolution row in
`docs/active-record-association-support.md`: `primary_key:`, explicit `source:`,
polymorphic `source_type:`, and specialized inverse `as:` bindings. The support
matrix, rather than every option accepted by every Active Record macro, is the
scope boundary.

This phase covers:

- scalar and ordered-composite explicit `primary_key:` on direct
  `belongs_to`, `has_many`, and `has_one`;
- explicit `primary_key:` when resolving direct polymorphic and delegated-type
  concrete targets;
- explicit through `source:` aliases;
- `source_type:` when the resolved through source is a polymorphic
  `belongs_to`;
- inverse `has_many` / `has_one ..., as:` whose interface, identifier tuple,
  type column, and referenced key are specialized but exactly match the root.

P2-05 does not add cross-domain publication (P2-06), behavior metadata (P2-07),
new relationship document fields, or a new HABTM identity. P1-07 already
normalizes HABTM custom join-table/key aliases from reflected join columns;
endpoint `primary_key:` values do not participate in its public many-to-many
identity. Unsupported composite HABTM remains the P2-04 probed boundary.

## Verified behavior snapshot

Current implementation rejects option presence before it evaluates the exact
resolved shape:

- direct `belongs_to` rejects every explicit `primary_key:` after reading the
  otherwise-valid key tuple;
- direct `has_many` / `has_one` returns a `:non_primary_key` sentinel except for
  a scalar option equal to the actual scalar owner primary key;
- through handling short-circuits explicit `source:` as
  `ASSOCIATION_MACRO_OMITTED` and `source_type:` as
  `ASSOCIATION_POLYMORPHIC_OMITTED`;
- through-hop physical validation repeats both direct option-presence gates;
- direct polymorphic roots require default `<interface>_id` /
  `<interface>_type` names even when Rails reflects valid custom columns;
- delegated-type preflight independently repeats the default-name and explicit
  `primary_key:` omissions in `SchemaProbe`;
- polymorphic candidate matching reads specialized referenced tuples but then
  converts a valid inverse/root mismatch into
  `ASSOCIATION_NON_PRIMARY_KEY_OMITTED`.

The policy is therefore duplicated between `SchemaProbe`, direct publication,
through validation, and polymorphic candidate matching. P2-05 must replace
presence gates with one reflected-shape rule rather than add more exceptions.

## Rails 7.2 and 8.1 source facts

The pinned Active Record rules are verified against the official 7.2.3.1 and
8.1.3 `activerecord/lib/active_record/reflection.rb` sources plus the Rails
Association Basics guide. The exact local matrix bundle paths are environment
dependent and are not stable evidence for this repository.

Both versions expose the same relevant boundaries:

1. `BelongsToReflection#association_primary_key(concrete_class)` returns the
   explicit `options[:primary_key]`, otherwise the concrete target's
   query-constraint/primary-key metadata. A polymorphic root still requires a
   concrete class argument; calling `klass` on the root remains forbidden.
2. `AssociationReflection#active_record_primary_key` returns scalar or array
   `options[:primary_key]` before model query constraints or the model primary
   key. Direct has-side resolution can trust this reader without separately
   interpreting option presence.
3. `ThroughReflection#source_reflection_name` uses explicit `source:` exactly.
   Without it, Rails searches singular/plural candidates and raises when the
   choice is ambiguous. `source_reflection` is therefore the authoritative
   resolved hop; guessing from the outer association name is unsafe.
4. `ThroughReflection#check_validity!` requires `source_type:` for a polymorphic
   source and rejects it for a non-polymorphic source. `derive_class_name` uses
   the concrete `source_type`, while `foreign_key`, `foreign_type`, and
   `active_record_primary_key` continue to delegate to the resolved source.
5. An inverse `as:` supplies the polymorphic interface, but Rails honors
   explicit `foreign_key`, `foreign_type`, and `primary_key`. Default column
   derivation from the interface is a fallback, not an eligibility rule.

The official Rails Association Basics guide documents the same public options:
`belongs_to :user, primary_key: "guid"`, explicit through `source:`, and the
requirement for `source_type:` when a through source is polymorphic.

## Executable pinned-runtime evidence

The research-relative `probes/specialized_options_probe.rb` (repository path
`docs/p2/05-specialized-association-options/probes/specialized_options_probe.rb`)
defines one in-memory application and was run successfully against the exact
Rails 7.2.3.1 and 8.1.3 matrix bundles. Both versions returned the same
normalized evidence:

| Case | Reflected foreign key | Reflected referenced key | Runtime |
|---|---|---|---|
| scalar `belongs_to primary_key:` | `account_code` | `external_code` | target loaded |
| scalar `has_many primary_key:` | `account_code` | `external_code` | member loaded |
| scalar `has_one primary_key:` | `account_code` | `external_code` | member loaded |
| composite `belongs_to primary_key:` | `account_tenant_code, account_local_code` | `tenant_code, local_code` | target loaded |
| composite `has_many primary_key:` | `account_tenant_code, account_local_code` | `tenant_code, local_code` | member loaded |
| composite `has_one primary_key:` | `account_tenant_code, account_local_code` | `tenant_code, local_code` | member loaded |
| explicit `source: :writer` | resolved source `writer` | target `P205Author` | contributor loaded |
| `source_type: P205Post` | `taggable_ref` + `taggable_kind` | `slug` | post loaded |
| specialized `has_many ..., as: :record` | `record_ref` + `record_kind` | `external_code` | both directions loaded |
| specialized `has_one ..., as: :record` | `record_ref` + `record_kind` | `external_code` | inverse loaded |
| delegated `primary_key: external_code` | `record_ref` + `record_kind` | `external_code` | declared target loaded |

For explicit and typed through associations, `collect_join_chain` contains the
outer declaration followed by the through hop; the resolved source name is
available separately from `source_reflection`. The public path must therefore
keep the existing normalization step that replaces the terminal outer name
with the resolved source name.

Probe commands:

```text
ASDF_RUBY_VERSION=4.0.6 BUNDLE_GEMFILE=fixtures/rails_matrix/bundles/7.2/Gemfile \
  BUNDLE_PATH=.bundle/rails-matrix/gems/4.0.6 asdf exec bundle exec ruby \
  docs/p2/05-specialized-association-options/probes/specialized_options_probe.rb

ASDF_RUBY_VERSION=3.3.12 BUNDLE_GEMFILE=fixtures/rails_matrix/bundles/8.1/Gemfile \
  BUNDLE_PATH=.bundle/rails-matrix/gems/3.3.12 asdf exec bundle exec ruby \
  docs/p2/05-specialized-association-options/probes/specialized_options_probe.rb
```

## Resolution conclusions

### Direct `primary_key:`

- `belongs_to`: normalize `foreign_key` and
  `association_primary_key(concrete_target)` as ordered tuples.
- direct `has_many` / `has_one`: normalize `foreign_key` and
  `active_record_primary_key` as ordered tuples.
- Accept scalar or composite tuples only when both are valid, equal-length, and
  every physical member exists on the holder/referenced entity.
- Preserve P2-04 relationship ID encoding, DB-FK evidence, nullability, exact
  unique-index evidence, cardinality, and canonical inverse grouping. A custom
  referenced tuple changes the ID only for a relationship that was previously
  omitted.
- A malformed reader or unequal tuple is
  `ASSOCIATION_COMPOSITE_KEY_OMITTED`; a valid tuple naming a missing physical
  column is `ASSOCIATION_KEY_COLUMN_MISSING`. A valid non-primary tuple is not
  itself an omission.

### Explicit through `source:`

- Trust only Rails' resolved `through_reflection`, `source_reflection`, and
  `collect_join_chain`; do not read the option string as a target.
- Keep the existing semantic ID and path normalization. The resolved source
  reflection name replaces the outer terminal name, so an alias does not leak
  declaration syntax into public identity.
- Apply the same physical-hop tuple validation used by inferred through paths.
- Missing/ambiguous/raising source resolution remains
  `ASSOCIATION_SOURCE_UNRESOLVED`; no guessed fallback is allowed.

### Polymorphic `source_type:`

- Require a present concrete type and a resolved polymorphic source reflection.
- Resolve the concrete target from the through reflection's safe `klass` /
  `source_type` path, never from a polymorphic root `klass` call.
- Validate the source identifier tuple, scalar type column, and concrete
  referenced tuple exactly as a direct polymorphic binding, including custom
  `foreign_key`, `foreign_type`, and `primary_key`.
- A valid typed through declaration publishes one semantic through edge to the
  selected concrete target. It does not create a second polymorphic edge family
  or encode the type literal in the public ID.
- Fix the failure boundary by resolution stage:
  - missing/raising `through_reflection` remains
    `ASSOCIATION_THROUGH_UNRESOLVED`;
  - ambiguous, missing, or raising `source_reflection` remains
    `ASSOCIATION_SOURCE_UNRESOLVED`;
  - a resolved non-polymorphic source with `source_type:`, or a resolved
    polymorphic source without a concrete type, is
    `ASSOCIATION_POLYMORPHIC_OMITTED`;
  - an unresolved concrete `source_type` constant is
    `ASSOCIATION_TARGET_UNRESOLVED`; renderability and domain failures retain
    their existing target/domain codes;
  - after a concrete target resolves, malformed/unequal key tuples are
    `ASSOCIATION_COMPOSITE_KEY_OMITTED`, and valid tuples with missing physical
    members are `ASSOCIATION_KEY_COLUMN_MISSING`.

### Specialized inverse `as:`

- Candidate matching is exact on: interface (`options[:as]`), holder child
  model, reflected identifier tuple, reflected type column, and concrete
  referenced tuple.
- Remove default `<interface>_id` / `<interface>_type` naming as an eligibility
  condition. It remains only Rails' default derivation.
- The root referenced tuple is read with
  `association_primary_key(concrete_target)`; the inverse tuple is read with
  `active_record_primary_key`. Both must agree and exist physically.
- Existing `has_one`, `has_many`, then lexical alias canonicalization remains;
  custom aliases or columns do not create duplicate edges.
- Delegated-type roots use the same binding rule after their provenance and
  type-whitelist checks. `SchemaProbe` should capture reflected data and
  physical-column viability, not maintain a second naming policy.

## Compatibility and failure policy

- All existing scalar/composite IDs remain byte-identical.
- Public IR/render-plan schemas stay at v4; no option strings or new metadata
  are emitted.
- Existing exact DB constraints remain the only evidence for tighter
  cardinality. An option declaration does not imply uniqueness or a database
  FK.
- Scopes remain metadata-only under P2-01 and compose with specialized options.
- Domain/connection boundaries remain P2-06 omissions and are not weakened.
- Every unsafe reflection reader remains rescue-wrapped. Partial success is
  preserved: one invalid alias/target cannot suppress valid siblings.

## Required real-app evidence

Unit doubles are insufficient for reflection options. Add a dedicated
`specialized_options` Rails matrix family and run it on every declared pair. Its
runtime oracle and exact generated artifacts must cover:

- scalar and composite custom direct keys in both orientations;
- valid and missing physical custom key columns;
- explicit source alias path normalization;
- polymorphic typed source with custom id/type/referenced key;
- direct polymorphic specialized `as:` in both directions;
- delegated-type explicit referenced key if Rails-generated metadata supports
  the declaration;
- invalid/ambiguous source and mismatch diagnostics where a real declaration
  can express them.

Use isolated doubles only for reader exceptions, malformed arrays, cycles, and
other states Rails refuses to construct.

## Sources

- `docs/active-record-association-support.md`
- `docs/p0-contract.md`
- `docs/p2/01-scoped-associations/design.md`
- `docs/p2/03-delegated-type/design.md`
- `docs/p2/04-composite-keys/design.md`
- `lib/rails_mmd/relationship_builder.rb`
- `lib/rails_mmd/schema_probe.rb`
- pinned Active Record 7.2.3.1 and 8.1.3 `reflection.rb` sources listed
  above
- <https://guides.rubyonrails.org/association_basics.html>
- <https://api.rubyonrails.org/v7.2/classes/ActiveRecord/Associations/ClassMethods.html>
- <https://api.rubyonrails.org/v8.1/classes/ActiveRecord/Associations/ClassMethods.html>

## Specialist research record

The Rails-runtime specialist confirmed the exact option readers, through
validity rules, polymorphic reader hazards, and reflected-column matching rule.
The architecture specialist found duplicated policy in direct, through,
polymorphic, and delegated paths and recommended one normalized key resolver
plus one shared polymorphic binding rather than option-specific exceptions.
Both independently required a checked real-Rails matrix family.

## Research review record

Round 1 architecture review required delegated-type runtime evidence and a
closed stage-by-stage typed-source diagnostic mapping. Both were added; its
follow-up returned no findings. Round 1 Rails review required direct
`has_one primary_key:` and inverse `has_one ..., as:` coverage on both pinned
versions plus an explicit repository-relative probe path. Those corrections
were added. Its follow-up required the remaining composite `has_one
primary_key:` branch; it now passes on both pinned versions. Final Rails
follow-up returned no findings. All research perspectives are clear.
