# P2-03 Delegated Type Design

Status: complete

## Goals

- Selecting a delegated-type owner draws its declared physical delegate family
  and one concrete relationship edge per eligible type.
- The Rails-generated type whitelist, not inverse associations, is candidate
  authority.
- Explicit exclusions, configured domain ownership, selected connection, and
  unsupported-key boundaries remain deterministic.
- Auto-expanded delegate nodes do not become general association owners.
- Existing IR v3, render-plan v3, relationship IDs, and Mermaid syntax remain
  backward compatible.

## Non-goals

- Composite keys and `query_constraints` (P2-04).
- Custom `primary_key`, `foreign_key`, `foreign_type`, `source`, `source_type`,
  or specialized `as` resolution (P2-04/P2-05).
- Cross-domain or cross-connection edges/external nodes (P2-06).
- Rendering `dependent`, `touch`, or `counter_cache` behavior (P2-07).
- Recursive family expansion from an auto-expanded delegate.
- Publishing an auto-expanded delegate's unrelated associations.

## Pipeline

```text
ModelInventory
  -> DomainResolver
       explicit records
       exact exclusions
       all-configured-domain ownership index
  -> SchemaProbe
       explicit + delegated-expanded physical entities
       entity selection origin
       normalized delegated families/target outcomes
  -> RelationshipBuilder
       ordinary owners: explicit only
       delegated candidates: normalized whitelist
       inverse: optional evidence only
  -> IR v3 -> render plan v3 -> existing Mermaid serializers
```

The new information is internal pipeline state. `IrBuilder` consumes only the
physical entities and published relationships, so entity origin and delegated
family records never enter public JSON.

## DomainResolver contract

Extend `DomainResolver::DomainResult` with:

```ruby
excluded_ruby_constants # sorted unique Array<String>
```

This is the domain's exact configured `exclude_models` intent, including names
whose inventory record is missing or non-renderable. Resolution diagnostics keep
their current behavior; carrying intent does not add diagnostics.

Extend `DomainResolver::Result` with:

```ruby
owned_domain_ids_by_constant # Hash<String, Array<String>>
```

Build the ownership index from every configured domain, not only the domains
selected by a CLI `--domain` filter. For each domain, use its exact
`include_models - exclude_models` strings. Keys and sorted unique domain-ID
arrays are deterministic. This index is configuration ownership, not a new
inventory validation pass, and must not emit diagnostics for unselected domains.

`DomainResult#records` remains unchanged: it contains only explicit selected,
renderable records in first-include order.

## Generate handoff

`Generate#internal_payloads` passes:

```ruby
schema_probe.probe(
  domains: resolved.domains,
  inventory_records: inventory.records,
  owned_domain_ids_by_constant: resolved.owned_domain_ids_by_constant
)
```

`SchemaProbe#probe` defaults the new keyword to `{}` for existing direct callers
and doubles. Exclusion intent travels inside each resolved domain.

## SchemaProbe internal contract

Extend `SchemaProbe::Entity` with:

```ruby
selection_origin # :explicit or :delegated_type_expanded
```

`nil` means `:explicit` for backward compatibility with existing unit helpers.

Extend `SchemaProbe::DomainResult` with:

```ruby
delegated_type_families # Array<DelegatedTypeFamily>
```

Add closed internal records:

```ruby
DelegatedTypeFamily = Struct.new(
  :owner_entity_id,
  :owner_ruby_constant,
  :association_name,
  :foreign_key,
  :foreign_type,
  :scoped,
  :root_diagnostic_code,
  :targets,
  keyword_init: true
)

DelegatedTypeTarget = Struct.new(
  :ruby_constant,
  :entity_id,
  :status,
  :diagnostic_code,
  keyword_init: true
)
```

Allowed target statuses are:

- `:selected`
- `:expanded`
- `:unresolved`
- `:excluded`
- `:not_renderable`
- `:other_connection`
- `:other_domain`

Only `:selected` and `:expanded` have an `entity_id` and can publish an edge.
Every other status has the exact relationship diagnostic code.

### Delegated-root provenance

Discover roots only from successfully probed explicit owners and direct
polymorphic `belongs_to` reflections.

For role `entryable`:

1. obtain `owner_model.method(:entryable_types)` without calling it;
2. obtain `ActiveRecord::DelegatedType.instance_method(:delegated_type)`;
3. compare their non-nil `source_location.first` values;
4. call `entryable_types` only when the files match.

Absence, nil source, a provenance mismatch, or a safe-call failure produces no
delegated family. The reflection then follows ordinary inverse-driven
polymorphism. An application-defined spoof method is never executed.

The supported runtime matrix pins Rails 7.2.3.1 and 8.1.3, where this provenance
relationship is verified. No absolute gem path or line number is embedded.

Normalize the returned values to non-empty strings, deduplicate, and sort by
full Ruby constant. An empty or invalid result produces a family with zero
targets so the relationship phase can emit the root unresolved warning.

### Root eligibility before expansion

Expansion must not leave orphan delegate nodes for a structurally unsupported
root. Before probing targets, assign `root_diagnostic_code` when:

- association name is unsafe: `ASSOCIATION_NAME_UNSUPPORTED_OMITTED`;
- foreign key or foreign type is non-scalar: `ASSOCIATION_COMPOSITE_KEY_OMITTED`;
- scalar foreign key/type is not the default `<role>_id` / `<role>_type`:
  `ASSOCIATION_POLYMORPHIC_OMITTED`;
- explicit `primary_key` specialization exists:
  `ASSOCIATION_NON_PRIMARY_KEY_OMITTED`;
- either holder key column is absent: `ASSOCIATION_KEY_COLUMN_MISSING`.

When `root_diagnostic_code` is present, do not expand or probe target records.
`RelationshipBuilder` publishes exactly that root diagnostic and does not add a
zero-target warning.

### Target classification and expansion

Evaluate each canonical declared constant in this order:

1. explicitly excluded from the current domain, even when no inventory record
   exists: `:excluded` /
   `DOMAIN_RELATIONSHIP_OMITTED`;
2. no inventory record: `:unresolved` /
   `ASSOCIATION_TARGET_UNRESOLVED`;
3. connection context differs from the owner: `:other_connection` /
   `DOMAIN_RELATIONSHIP_OMITTED`;
4. the ownership index contains only other domain IDs: `:other_domain` /
   `DOMAIN_RELATIONSHIP_OMITTED`;
5. inventory record is not renderable: `:not_renderable` /
   `ASSOCIATION_TARGET_NOT_RENDERABLE_OMITTED`;
6. record is already explicit in this domain and has a successfully probed
   entity: `:selected`;
7. otherwise probe it once, add an entity with
   `selection_origin: :delegated_type_expanded`, and record `:expanded`.

If an explicit or expanded record cannot publish an entity, record
`:not_renderable` / `ASSOCIATION_TARGET_NOT_RENDERABLE_OMITTED` and also keep
the more specific existing schema-probe diagnostic. The two diagnostics describe
different public boundaries and prevent an incomplete family outcome.

Cache expanded probes by Ruby constant. Multiple roots can reuse the same
physical entity without repeated schema reads or diagnostics. Final entities
remain deterministically sorted through existing downstream rules.

Only explicit entities trigger STI subtype expansion, delegated-family
discovery, and hidden join-table probing. An auto-expanded delegate is a
physical node and relationship target only.

## RelationshipBuilder contract

### Owner inventory fence

Ordinary reflection inventory includes only entities whose
`selection_origin != :delegated_type_expanded`. A missing origin remains
explicit. This prevents auto-expanded targets from publishing unrelated direct,
through, HABTM, or polymorphic relationships and from recursively expanding a
delegated family.

Targeted inverse inspection is allowed only while resolving one normalized
delegated target. It must not add that target to ordinary owner inventory.

### Delegated roots

Index normalized families by `[owner_entity_id, association_name]`. A
polymorphic root with no matching family keeps the P1-06 inverse-driven path.
A matching family uses the normalized whitelist path:

1. publish `root_diagnostic_code` and stop if present;
2. convert every target diagnostic into the existing `omitted` diagnostic with
   the declared target constant in metadata;
3. resolve `:selected` / `:expanded` targets from `context.entity_by_constant`;
4. inspect only those target models for matching direct polymorphic inverses;
5. publish one existing-shape polymorphic edge per surviving target even when
   no inverse exists;
6. when none survive, append exactly one
   `ASSOCIATION_POLYMORPHIC_TARGETS_UNRESOLVED` root warning.

An inverse is valid evidence only when its `as:` interface matches the role, its
child resolves to the delegator model, its scalar id/type columns match the
root, and its referenced key matches the target's scalar physical primary key.
Canonicalize duplicates by existing macro/lexical priority. Any valid `has_one`
inverse or total unique holder `(type, id)` index makes the owner cardinality
`0..1`; otherwise it is `0..many`. Target cardinality remains `0..1`.

Root scope or any canonical matching inverse scope produces
`metadata.scoped: true`; no scope proc is called.

Declared invalid inverses emit existing target-specific omission diagnostics
but do not suppress an otherwise valid declared edge. An explicit undeclared
inverse is not handled by the family and remains on the existing
`ASSOCIATION_POLYMORPHIC_OMITTED` leftover path.

### Identity and ordering

Keep existing relationship identity:

```text
relationships/<holder_table>/polymorphic/<role>/<id_column>/<type_column>/<target_table>
```

Keep `relationship_kind: :polymorphic` internally. Family records sort by
`[owner_entity_id, association_name]`; targets sort by full constant; final
relationships retain the existing `relationship_id` sort. Diagnostics sort by
this delegated-root append rule without globally reordering existing phases:

1. delegated roots by `[owner_entity_id, association_name]`;
2. within one root, target-status diagnostics by full target constant;
3. declared-target invalid-inverse diagnostics by
   `[target constant, inverse association name]`;
4. the single root `ASSOCIATION_POLYMORPHIC_TARGETS_UNRESOLVED` last when no
   edge survives;
5. after all roots, leftover undeclared inverse omissions by
   `[owner entity_id, association name]`.

A structural `root_diagnostic_code` is the root's sole delegated diagnostic and
stops before steps 2--4. Ordinary and generic-polymorphic phase ordering remains
unchanged.

## Public artifacts

- IR schema remains version 3.
- Render-plan schema remains version 3.
- Expanded delegates are ordinary physical entities with normal attributes.
- Relationship metadata remains absent or `{ "scoped": true }`.
- ER and class diagrams use existing entity and concrete relationship syntax.
- No origin, family, declared-type, or runtime-provenance metadata is published.
- Namespaced same-leaf physical models remain distinct entity IDs/tokens and
  retain existing safe-token collision diagnostics; P2-03 does not redesign
  global physical labels.

## TDD vertical slices

Each slice begins with an observed public-seam failure.

1. `DomainResolver#resolve`: all-configured-domain ownership and exact exclusion
   intent survive a CLI domain filter.
2. `Generate`: new ownership handoff reaches `SchemaProbe#probe` exactly.
3. `SchemaProbe#probe`: a selected delegator expands same-connection declared
   types and returns closed normalized families/entity origins.
4. `SchemaProbe#probe`: a spoofed application `<role>_types` method is neither
   called nor accepted.
5. `SchemaProbe#probe`: exclusion, non-renderable, other-connection,
   other-domain, unresolved, failed-probe normalization to
   `ASSOCIATION_TARGET_NOT_RENDERABLE_OMITTED` plus the retained schema-probe
   diagnostic, and no-recursion boundaries are exact and deterministic.
6. `RelationshipBuilder#build`: a delegated root publishes declared targets
   without inverses and filters undeclared inverses.
7. `RelationshipBuilder#build`: optional inverse/unique-index cardinality,
   scoped metadata, invalid-inverse partial success, and owner fencing are exact.
8. `RelationshipBuilder#build`: target diagnostics plus the single zero-target
   warning are complete-array deterministic.
9. Shared real Rails matrix: exact runtime whitelist/provenance, physical nodes,
   relationship/group projections, diagnostics, and both Mermaid artifacts pass
   every Ruby/Rails pair.

Do not test private helpers. Test the public result records and emitted
artifacts, including negative absence assertions.

## Real Rails matrix plan

Add one selected delegator and declare:

- two same-connection namespaced targets with the same leaf constant, one with
  a canonical inverse whose scope proc raises if executed and one with no
  inverse;
- a selected STI base target to prove physical-endpoint composition;
- an STI leaf target to prove non-renderable omission;
- an explicitly excluded target to prove family expansion respects config;
- a target assigned only to a configured second domain to prove end-to-end
  `DOMAIN_RELATIONSHIP_OMITTED` without an external node or cross-domain edge;
- an undeclared selected model with a matching inverse to prove whitelist
  authority.

The second-domain fixture uses the same database connection and contains no
cross-domain edge support; it proves only ownership fencing. Unit tests cover
the different-connection case to avoid turning the shared fixture into a
multi-DB P2-06 implementation.

Add a fixture-owned delegated runtime script and exact JSON expectation for:

- reflection macro/polymorphic flag/default keys;
- declared `<role>_types` in Rails order;
- `generated_source_matches_runtime_delegated_type_source: true`, computed by
  exact equality with the running Rails implementation's source file;
- the normalized source suffix
  `activerecord/lib/active_record/delegated_type.rb`, never a machine-local
  absolute prefix;
- namespaced types.

Extend `ArtifactValidator` with missing, malformed, and mismatched delegated
runtime-oracle regressions through the shared controlled expected-JSON reader.
Update existing exact relationship, polymorphic-group, diagnostic, ER Mermaid,
and class Mermaid expectations. No new public rails-mmd artifact is introduced.

## File-level implementation plan

- `lib/rails_mmd/domain_resolver.rb`
- `lib/rails_mmd/generate.rb`
- `lib/rails_mmd/schema_probe.rb`
- `lib/rails_mmd/relationship_builder.rb`
- matching public specs under `spec/rails_mmd/`
- `fixtures/rails_matrix/template/{app/models,db/schema.rb,rails_mmd.yml,script}`
- existing exact matrix expectations
- `tooling/rails_matrix.rb`
- `spec/integration/rails_matrix_task_spec.rb`
- `docs/p0-contract.md` for the explicit P2-03 family-selection exception
- `docs/active-record-association-support.md`
- `README.md` only if user-visible selection behavior is documented there
- `AGENTS.md` only for the verified durable Rails reflection/provenance and
  normalized-handoff rules after implementation review

## Verification gates

- focused red/green specs and RuboCop after every slice;
- contract fixtures remain v3 and pass unchanged;
- full RSpec and Undercover for changed production lines;
- Bundler Audit;
- all three real Rails matrix pairs;
- `git diff --check`;
- direct pre-commit and pre-push hooks.

## Design review record

| Round | Perspective | Finding | Correction |
|---|---|---|---|
| 1 | Rails runtime | Cross-domain/renderability precedence, same-leaf namespace proof, and runtime provenance evidence were too weak | Made domain/connection fences precede renderability, required same-leaf namespaced delegates, and asserted exact same-source truth plus normalized suffix |
| 1 | Internal API | `:probe_failed` broke the closed target outcome and diagnostic ordering was unspecified | Normalize failed probes to `:not_renderable` plus schema evidence and define the delegated diagnostic append order |
| 1 | QA / TDD | Other-domain ownership was not covered by the real matrix | Added a same-connection second-domain fixture and exact absence/diagnostic oracle |
| 2 | Rails runtime | A missing but explicitly excluded declaration was classified as unresolved | Made exact exclusion intent the first target classification rule |
| 2 | Internal API, QA / TDD | The TDD seam still named a removed `:probe_failed` state | Fixed the public oracle to target-not-renderable plus the retained schema diagnostic |
| 3 | Rails runtime, internal API, QA / TDD | No findings | None |
