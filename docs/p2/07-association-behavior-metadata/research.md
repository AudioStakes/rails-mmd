# P2-07 association behavior metadata research

## Target and boundary

P2-07 represents the Rails association behaviors declared with `dependent`,
`touch`, and `counter_cache` on relationships that rails-mmd already publishes.
It owns normalized, non-executing behavior metadata only. It does not execute
callbacks, mutate records, infer undeclared callbacks, publish arbitrary Rails
options, or reopen structural eligibility decided by P2-01 through P2-06.

Behavior metadata is advisory success-path data. An unreadable or unsupported
behavior value must not make an otherwise valid structural edge disappear.
Domain, connection, key, through, polymorphic, delegated-type, and HABTM gates
continue to run before metadata can reach a published edge.

## Rails facts

### Direction is part of the behavior

The three options are declaration-local callback behavior, not undirected
physical-edge attributes:

- `belongs_to dependent:` is triggered when the foreign-key holder is
  destroyed and acts on the referenced record;
- inverse `has_one` / `has_many dependent:` is triggered when the referenced
  owner is destroyed and acts on the foreign-key holder record(s);
- `belongs_to touch:` is triggered by the foreign-key holder and touches its
  referenced record;
- `has_one touch:` is triggered by the declaration owner and touches its
  associated foreign-key holder;
- a real counter-cache callback is owned by `belongs_to`; lifecycle changes on
  the foreign-key holder update a column on the referenced record.

rails-mmd canonicalizes a direct relationship around the physical foreign-key
holder. Reciprocal declarations therefore collapse onto one edge even though
their lifecycle triggers point in opposite directions. Any public contract that
flattens behavior to one scalar per edge loses Rails semantics.

### Supported macro surface

Rails 7.2.3.1 and 8.1.3 have the same P2-07-relevant boundaries:

| Declaration | `dependent` | `touch` | `counter_cache` |
|---|---|---|---|
| `belongs_to` | `destroy`, `delete`, `destroy_async` | `true` or named attribute | lifecycle source; default, named, and inactive/custom shapes |
| direct `has_one` | `destroy`, `destroy_async`, `delete`, `nullify`, `restrict_with_error`, `restrict_with_exception` | `true` or named attribute | no declaration-owned lifecycle callback |
| direct `has_many` | `destroy`, `destroy_async`, `delete_all`, `nullify`, `restrict_with_error`, `restrict_with_exception` | unsupported | raw option is inverse cache naming/configuration, not its own lifecycle callback |
| `has_one :through` | accepted but ignored | supported by the outer singular declaration | no lifecycle callback |
| `has_many :through` | acts on join/through records, not the terminal target | unsupported | no lifecycle callback |
| HABTM | no declared P2-07 behavior; unknown raw options can remain visible on the parent reflection but are not wired into the generated association | none | none |

A polymorphic `belongs_to` has the ordinary `belongs_to` behavior surface. A
matching inverse `as:` reflection has its ordinary `has_one` / `has_many`
surface. `delegated_type` forwards its options to the generated polymorphic
`belongs_to`, so its root uses the same rules. rails-mmd must continue never to
call `klass` on a polymorphic root.

### Normalized values

`MacroReflection#normalize_options` converts every truthy counter-cache option
to a hash:

```ruby
{ active: true, column: nil }
{ active: true, column: "custom_count" }
{ active: false, column: "custom_count" }
```

The stable public form should use the derived `counter_cache_column` and the
normalized active state, never raw Ruby option polymorphism:

```json
{ "column": "p207_members_count", "active": true }
{ "column": "custom_members_count", "active": false }
```

Normalize `dependent` symbols to a closed string enum. Normalize touch as
`{"attribute": null}` for `true` and `{"attribute": "column_name"}` for a
named touch. This distinguishes the default timestamp set from a custom
attribute without serializing Ruby values.

Reading `reflection.options`, `counter_cache_column`, `has_cached_counter?`, and
`has_active_cached_counter?` observes Rails metadata and does not execute an
association scope or application callback. Every reader still needs the
existing safe containment boundary because applications may monkey-patch
reflection objects.

## Executable pinned-version evidence

`probes/behavior_options_probe.rb` declares direct, through, polymorphic,
delegated-type, inverse-counter-naming-only, and HABTM associations. Its Rails
evidence layer records raw reflected behavior values after Rails' own option
normalization plus the derived counter-cache readers. A separately labelled
`proposed_public_declaration` layer previews the pure rails-mmd normalization
proposed below; it is not upstream Rails evidence and does not prove the public
directional grouping or schema. Builder/schema tests must prove that contract.
The probe does not create, save, destroy, or touch records.

The probe passed on Active Record 7.2.3.1 and 8.1.3. Removing only
`rails_version` made the JSON documents byte-equivalent. Confirmed evidence:

- `belongs_to counter_cache: true` becomes
  `{active: true, column: null}` and derives `p207_members_count`;
- inactive custom counter cache becomes
  `{active: false, column: "custom_members_count"}`;
- an isolated `has_many counter_cache: :inverse_named_members_count`
  declaration retains the inverse naming option while its paired `belongs_to`
  declares no lifecycle counter cache; the proposed public projection therefore
  excludes the `has_many` option instead of misreporting it as a callback;
- custom `touch` symbols remain named option values, while `touch: true`
  remains boolean;
- delegated-type root options match polymorphic `belongs_to` normalization;
- through reflections retain outer `dependent`, including the ignored
  `has_one :through` case;
- the HABTM parent reflection echoes unsupported raw options even though the
  HABTM builder does not wire them into the generated relationship. Reflection
  presence alone is therefore insufficient evidence of effective behavior.
  the raw value and truthiness of `has_cached_counter?`, plus
  `has_active_cached_counter?`, are recorded separately from that option echo.

Preliminary local source-version checks used Active Record 7.2.3.1 and 8.1.3.
The 8.1.3 source check under Ruby 4.0.5 is not support-matrix evidence. The same
probe then passed on all three declared pairs: Ruby 4.0.6/Rails 7.2, Ruby
3.3.12/Rails 8.1, and Ruby 4.0.6/Rails 8.1. Excluding only `rails_version` made
all three exact-pair JSON documents byte-equivalent. Representative exact-pair
commands are:

```text
ASDF_RUBY_VERSION=4.0.6 \
BUNDLE_GEMFILE=fixtures/rails_matrix/bundles/7.2/Gemfile \
BUNDLE_PATH="$PWD/.bundle/rails-matrix/gems/4.0.6" \
asdf exec bundle exec ruby \
docs/p2/07-association-behavior-metadata/probes/behavior_options_probe.rb

ASDF_RUBY_VERSION=3.3.12 \
BUNDLE_GEMFILE=fixtures/rails_matrix/bundles/8.1/Gemfile \
BUNDLE_PATH="$PWD/.bundle/rails-matrix/gems/3.3.12" \
asdf exec bundle exec ruby \
docs/p2/07-association-behavior-metadata/probes/behavior_options_probe.rb
```

The delivery matrix must additionally run this evidence and the exact artifact
oracle on all three declared Ruby/Rails pairs. Probe equivalence is not a
substitute for the matrix gate.

## Repository facts

- `RelationshipBuilder` is the first stage that owns both selected endpoints
  and Rails reflections. `SchemaProbe` owns database metadata and must not gain
  behavior-option access.
- Internal `Relationship#metadata`, `IrBuilder`, and `RenderPlanBuilder`
  currently understand only `scoped: true`.
- IR and render-plan schemas close `relationship_metadata` and require its only
  current member, `scoped`. P2-07 therefore intentionally expands the public
  relationship schema; old strict consumers would reject the new shape.
- P2-01 established that successful association annotations belong in
  machine-readable IR/render-plan metadata, not diagnostics or Mermaid label
  decoration. It bumped both public artifact schema versions for that reason.
- P2-04 later moved both artifact schemas to v4. P2-05 and P2-06 explicitly
  deferred behavior options to P2-07 and preserved v4.
- Canonical deduplication chooses identity/label/cardinality winners separately
  for direct, through, polymorphic, and HABTM groups. Its metadata merge is only
  boolean OR for `scoped`, so P2-07 needs a declaration-aware merge.
- The matrix relationship oracle already exact-compares optional metadata, but
  no real fixture declares or validates P2-07 behavior.

## Public contract alternatives

### A. Flat edge-level behavior fields

Rejected. A scalar `dependent` or one flat option object cannot say whether the
canonical owner or target lifecycle triggers it. Aliases and reciprocal
declarations can also contribute different values to one physical edge, making
winner-based or boolean-OR merging order-sensitive or lossy.

### B. Private sidecar plus decorated Mermaid label

Rejected for P2-07 after weighing its smaller public surface. The current token
context is auxiliary but is deterministically derived from public IR; it does
not introduce relationship semantics absent from IR. A behavior sidecar would
instead become a second semantic source of truth, prevent the render plan from
being reproduced from public IR plus deterministic tokenization, and reverse
the P2-01 decision that successful annotations are machine-readable metadata
rather than edge-label text. A visible label policy can be added later from the
normalized public data without changing its meaning.

### C. Directional declaration-aware public metadata

Selected for design. Bump IR and render-plan schema versions from 4 to 5 and
extend the existing closed metadata object with optional `behavior` alongside
optional `scoped`. Behavior is grouped by the canonical endpoint whose
lifecycle triggers it. Each side is a sorted array of declaration records so
aliases and conflicts remain lossless:

```json
{
  "metadata": {
    "scoped": true,
    "behavior": {
      "from_owner": [
        {
          "association_name": "account",
          "association_macro": "belongs_to",
          "dependent": {
            "action": "delete",
            "target": "associated_records"
          },
          "touch": { "attribute": "members_touched_at" },
          "counter_cache": {
            "column": "p207_members_count",
            "active": true
          }
        }
      ],
      "from_target": [
        {
          "association_name": "members",
          "association_macro": "has_many",
          "dependent": {
            "action": "destroy",
            "target": "associated_records"
          }
        }
      ]
    }
  }
}
```

`from_owner` / `from_target` refer to canonical public relationship endpoints,
not declaration macro names. `association_macro` preserves the declaration
kind after reciprocal and alias collapse. A declaration record contains at
least one behavior option. `dependent.target` is `associated_records` for direct,
polymorphic, and delegated-type declarations, and `through_records` for a
supported `has_many :through` declaration. Ignored `has_one :through
dependent` and all HABTM raw P2-07 options are absent, not mislabeled as
effective.

Arrays are sorted by canonical JSON content after exact duplicate removal.
Winner selection never discards behavior. If the relationship has neither
scope nor behavior, `metadata` stays absent; existing behavior-free IR,
render-plan, and Mermaid bytes otherwise remain stable apart from the required
top-level schema-version change.

Both public artifacts carry the same relationship metadata intentionally.
P2-01 already superseded the P0 renderer-only boundary by adding `scoped` to
IR and render plans while leaving Mermaid unchanged. Keeping behavior metadata
identical follows that precedent, lets independent render-plan consumers
annotate behavior without a private semantic sidecar, and preserves the
deterministic IR-to-render-plan projection. Mermaid serialization remains
unchanged in P2-07.

The version migration is atomic: generated IR and render plans both move to v5
in the same release, with no v4 compatibility or dual-version output mode.
Strict consumers must update to the v5 schemas shipped with that release before
consuming its artifacts. The durable user-facing migration notice belongs in
README's `Artifact Schema Versions` section and is a required implementation
deliverable, not release-note follow-up. Configuration and diagnostic artifact
versions remain unchanged.

## Risks and required boundaries

- Never execute callbacks, scopes, association accessors, or persistence
  methods while extracting metadata.
- Do not infer effective behavior merely because an unsupported raw option is
  present on HABTM or ignored `has_one :through` reflections.
- Preserve inactive counter-cache state; it is not equivalent to absence.
- Retain every behavior-bearing declaration through reciprocal/alias dedup in
  deterministic order.
- Behavior extraction failure is advisory: keep the structural edge and omit
  only unreadable behavior data.
- Polymorphic and delegated root behavior is copied to each surviving concrete
  edge; rejected domain/connection candidates publish no edge metadata.
- Through-record `dependent` must never be presented as terminal-target
  deletion behavior.
- Safe-token identity, relationship IDs, cardinality, Mermaid labels, and
  comments do not depend on behavior metadata.
- Schema v5 must reject empty behavior objects/arrays, unknown keys, invalid
  actions/targets, malformed touch attributes, invalid counter columns, and
  behavior declaration records with no option.

## Required public test boundaries

- Schema fixtures and contract tests for v5 scoped-only, behavior-only, mixed,
  both directions, inactive counter cache, and every closed-shape rejection.
- README migration guidance stating the lockstep v5 move, no dual-version
  output, and same-release schema requirement.
- `RelationshipBuilder#build` for direct `belongs_to` / `has_one` / `has_many`,
  reciprocal alias merge, exact duplicate removal, and canonical-JSON ordering
  of multiple records within each direction; `has_many :through` join-record
  semantics; ignored `has_one :through dependent`; polymorphic root/inverse;
  delegated root; cross-domain/cross-connection candidates; and unreadable
  options.
- `IrBuilder#build` and `RenderPlanBuilder#build` for exact normalized metadata
  propagation and behavior-free omission.
- A dedicated real `association_behavior` matrix family with runtime probe and
  exact entities, relationships, diagnostics, IR/render-plan metadata, and
  behavior-free Mermaid oracles on every declared pair.
- Task-level negative cases for missing, malformed, and mismatched behavior
  runtime evidence, plus missing, malformed, and mismatched artifact
  expectations.
- Undercover coverage for every safe-reader fallback and ignored macro branch.

## Research review record

| Round | Specialist lens | Findings resolved | Result |
|---|---|---|---|
| 1 | Rails semantics | Separated upstream reflection evidence from the proposed public projection and added derived counter-cache reader evidence | corrected |
| 1 | Architecture/API | Preserved `association_macro`, justified lockstep IR/render-plan metadata, evaluated the sidecar tradeoff, and distinguished preliminary from declared-pair evidence | corrected |
| 1 | QA/evidence | Preserved the raw `has_cached_counter?` value with correct truthiness and isolated inverse-only counter naming from the lifecycle source | corrected |
| 2 | Rails semantics | No remaining finding | `指摘なし` |
| 2 | Architecture/API | Made the atomic v5 migration, no-dual-output policy, and README ownership explicit | corrected |
| 2 | QA/evidence | Added explicit ordering/dedup seams and missing/malformed/mismatched matrix failure coverage | corrected |
| 3 | Architecture/API | No remaining finding | `指摘なし` |
| 3 | QA/evidence | No remaining finding | `指摘なし` |

## Sources

- Rails 7.2.3.1 `activerecord/lib/active_record/reflection.rb`
- Rails 7.2.3.1 `activerecord/lib/active_record/associations/builder/*.rb`
- Rails 8.1.3 `activerecord/lib/active_record/reflection.rb`
- Rails 8.1.3 `activerecord/lib/active_record/associations/builder/*.rb`
- Rails 7.2.3 Association Basics and API documentation
- Rails 8.1.3 Association Basics and API documentation
- `docs/active-record-association-support.md`
- `docs/p2/01-scoped-associations/{research,design}.md`
- `docs/p2/03-delegated-type/{research,design}.md`
- `docs/p2/05-specialized-association-options/research.md`
- `docs/p2/06-cross-domain-multi-db/research.md`
- `lib/rails_mmd/relationship_builder.rb`
- `lib/rails_mmd/ir_builder.rb`
- `lib/rails_mmd/render_plan_builder.rb`
- `schemas/ir.schema.json`
- `schemas/render_plan.schema.json`
- `spec/contracts/schema_spec.rb`
- `tooling/rails_matrix.rb`
