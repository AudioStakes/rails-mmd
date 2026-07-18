# P2-05 Specialized Association Options Implementation

Status: complete

## Planned TDD slices

1. shared association binding resolver;
2. direct explicit `primary_key:` publication;
3. specialized polymorphic and delegated bindings;
4. explicit through `source:` resolution;
5. typed polymorphic through `source_type:` resolution;
6. exact real-Rails matrix family;
7. cumulative contract and durable guidance.

## TDD evidence

### Slice 1: shared association binding resolver

- RED: loading `RailsMmd::AssociationBindingResolver` failed because the module did not exist.
- Intermediate RED: 8 examples, 1 failure exposed acceptance of a non-scalar polymorphic type column.
- GREEN: 8 examples, 0 failures.
- Targeted lint: 3 files inspected, no offenses.

The resolver now owns Active Record reader-arity differences, scalar/composite tuple normalization,
type-column selection, width validation, and closed failure mapping. Returned tuples and members are
frozen so callers cannot mutate normalized reflection metadata.

### Slice 3a: delegated-family probe preflight

- RED: 2 focused examples, 2 failures. Custom identifier/type columns were rejected as polymorphic,
  and a valid `primary_key:` declaration was rejected as non-primary.
- GREEN: 2 focused examples, 0 failures; all 38 `SchemaProbe` examples, 0 failures.
- Targeted lint: 2 files inspected, no offenses; `git diff --check` clean.

Delegated preflight now delegates structural key/type validation to `polymorphic_root`; it no longer
assumes Rails' default column names or resolves a target-specific referenced key during schema probing.

### Slice 2: direct explicit `primary_key:` bindings

- RED: 4 focused examples, 4 failures, all caused by the former option-presence omission.
- GREEN: 4 focused examples, 0 failures; all 76 `RelationshipBuilder` examples, 0 failures.
- Targeted lint: 2 files inspected, no offenses; `git diff --check` clean.

Direct `belongs_to`, `has_many`, and `has_one`, plus physical direct hops inside through paths, now
consume resolver bindings. The `:non_primary_key` sentinel and explicit-option gates are gone while
malformed tuples, missing columns, identity, cardinality, and canonicalization retain their existing
diagnostics and rules.

### Initial integration checkpoint

The resolver, schema-probe, and relationship-builder specs pass together: 122 examples, 0 failures.

### Slices 3b–5: specialized polymorphic and through bindings

The relationship builder now:

- uses shared root, concrete-target, and inverse bindings for ordinary polymorphic and delegated edges;
- removes default polymorphic column-name eligibility checks;
- publishes explicit `source:` paths from Rails' resolved source reflection;
- classifies typed-source reflection exceptions without loading Rails exception constants;
- injects the concrete target from the owning typed through reflection and never calls `klass` on a
  polymorphic source;
- validates every physical direct hop with private `ThroughPhysicalHop` descriptors; and
- keeps the public through identifier based on the resolved semantic path, without encoding option syntax.

Focused contracts include custom scalar polymorphic keys, inverse-free delegated custom keys,
explicit and nested sources, typed sources with custom identifier/type/referenced keys, invalid typed
structures, source-reader failures, and scalar/composite physical-hop checks.

### Implementation review and repair loop 1

Rails and architecture specialists reported five medium findings:

1. mutable resolver result/binding envelopes;
2. an over-broad through physical-analysis rescue that mislabeled unrelated faults as composite omissions;
3. inverse-polymorphic inventory based on `type` rather than `options[:as]`;
4. silently discarded ordinary polymorphic inverse target failures; and
5. typed through semantic target selection depending on join-chain terminal shape.

Each finding received a regression-first repair. Observed RED evidence included a mutable-envelope
failure, a swallowed unrelated context exception, an ordinary `has_many` misclassified solely by a
`type` reader, an unresolved inverse collapsed into root warnings, and a typed join chain ending in its
polymorphic source resolving to `Taggable` instead of the concrete `Article`. After repair, the focused
suite passes with 126 examples and no failures; seven changed Ruby/spec files have no RuboCop offenses.

The same Rails and architecture specialists then re-reviewed the repairs. Both returned `指摘なし`.

### Slice 6: real Rails matrix family

- RED: the integration contract expected `specialized_options` in the manifest and runtime-oracle
  registry; the focused example failed because neither was registered.
- GREEN: the family is registered and its focused integration example passes.
- Real-app GREEN: `specialized_options` passes on every declared pair:
  - Ruby 4.0.6 / Rails 7.2.3.1;
  - Ruby 3.3.12 / Rails 8.1.3;
  - Ruby 4.0.6 / Rails 8.1.3.

The checked-in family covers scalar and composite direct `primary_key:` bindings in both
orientations, direct `has_one`, explicit through `source:`, typed polymorphic `source_type:` with
custom identifier/type/referenced columns, specialized `has_many` and `has_one ..., as:`, and a
custom-key delegated type. Its runtime oracle verifies both reflection metadata and actual loads;
its artifact oracles lock exact relationships, polymorphic groups, diagnostics, and Mermaid output.

### Implementation review and repair loop 2

The matrix QA review found one medium gap: generic registration was covered, but cheap fake-harness
regressions did not select the new family or exercise missing/mismatched runtime expectations. Three
tests were added regression-first. The two runtime cases failed with missing helper seams, then all
three passed after wiring the specialized runtime knobs. Contract/documentation review found only the
intentionally pending verification status; after clarifying it, the re-review returned `指摘なし`.

## Verification record

- Full RSpec suite: 393 examples, 0 failures.
- RuboCop: 146 files inspected, no offenses.
- Bundler Audit: no vulnerabilities found.
- Undercover: no coverage missing in the latest changes. The first run exposed four uncovered
  branches; targeted regressions covered polymorphic-root reader failure, root-binding failure,
  referenced-key mismatch, and nested physical-through recursion, while one logically redundant
  post-equality column check was removed.
- Rails matrix: all four fixture families pass on all three declared Ruby/Rails pairs.
- Specialized-options harness spec: 41 examples, 0 failures.
- Direct local pre-commit hook: passed with the complete staged change set.
- Direct local pre-push hook: passed with the complete staged change set.

## Implementation review record

- Core implementation Rails and architecture repair re-reviews: `指摘なし`.
- Matrix QA repair re-review: `指摘なし`.
- Contract/documentation repair re-review: `指摘なし`.
