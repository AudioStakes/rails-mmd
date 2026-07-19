# P2-06 cross-domain / multi-DB implementation

Status: implementation complete

## TDD record

### Slice 1: diagnostic contract and collision-only schema probe

- RED: `primitives_spec` could not build the unknown
  `CONNECTION_RELATIONSHIP_OMITTED` catalog entry, and `schema_probe_spec` proved
  that distinct tables on two contexts still triggered the broad fatal (3
  failures, seed 18407).
- GREEN: the closed diagnostic and collision-only gate pass primitives,
  schema-probe, and contract schema coverage (73 examples, seed 42797).

### Slice 2: direct relationship boundaries

- RED: cross-context `belongs_to` reached a forbidden key reader and became a
  composite-key warning; `has_one` and `has_many` both rendered cross-context
  edges (2 failures, seed 52265).
- GREEN: the normalized endpoint seam rejects `belongs_to`, `has_one`, and
  `has_many` before binding/DB evidence (82 examples, seed 5724).

### Slice 3: through relationship boundaries

- RED: a first-hop context mismatch still published both the through edge and a
  physical direct edge (focused failure, seed 52653).
- GREEN: semantic and normalized physical hop walks share the endpoint gate;
  focused relationship coverage passes (83 examples, seed 42804).

### Slice 4: polymorphic and delegated-type boundaries

- RED: a mixed polymorphic group rendered both archive-context candidates
  instead of keeping only the primary candidate (focused failure, seed 5709).
  Delegated normalization also labeled a connection boundary as a domain
  omission and let connection precedence hide other-domain ownership (focused
  failure, seed 31391). An unhandled inverse still collapsed a resolvable
  cross-context holder into the generic polymorphic warning (focused failure,
  seed 62819).
- GREEN: mixed concrete candidates preserve local edges, candidate-specific
  boundary warnings replace cross-context edges, delegated ownership precedes
  connection classification, and rootless inverses classify only safe resolved
  boundaries. Existing same-context generic diagnostic bytes remain unchanged
  (focused schema/relationship suite: 124 examples, seed 26509 after repair).

### Slice 5: HABTM context isolation and IR invariant

- RED: two owner connections exposing the same hidden join-table name collapsed
  into one context-free record (focused failure, seed 49445). `IrBuilder` also
  silently projected duplicate physical IDs instead of rejecting its invalid
  handoff (focused failure, seed 40421). A delegated-expansion seam then proved
  the schema-probe handoff lacked its final collision recheck (focused failure,
  seed 5549).
- GREEN: hidden join-table records and lookups are context-qualified, HABTM and
  physical-through gates precede key readers, SchemaProbe rechecks the final
  expanded entity set, and IrBuilder rejects duplicate physical IDs (focused
  core suite: 138 examples, seed 14740; relationship suite: 87 examples, seed
  48980).

### Slice 6: real matrix and public contract

- RED: the integration contract initially reported no P2-06 runtime oracle or
  pair probe. The first real fixture then exposed two harness defects: loading a
  family schema replaced the shared STI tables, and the primary-side schema did
  not preserve the exact foreign-key evidence required by the oracle. The fake
  runner also rejected missing probe/runtime/collision outputs.
- GREEN: a family-local additive schema setup, exact runtime/probe/artifact
  oracles, and a diagnostics-only collision invocation now pass the focused
  matrix runner suite (47 examples, seed 2606). The mandatory real matrix passes
  every family, including `cross_domain_multi_db`, on all three declared pairs:
  Ruby 4.0.6 / Rails 7.2.3.1, Ruby 3.3.12 / Rails 8.1.3, and Ruby 4.0.6 /
  Rails 8.1.3 (`PASS 3/3 Rails matrix pairs`).

### Review repair: single-context diagnostic non-regression

- RED: the restored P2-03 domain-only delegated-type oracle expected the generic
  root warning after its candidate-specific warnings; the first P2-06 draft
  suppressed it together with the new connection warning (133 examples, 1
  failure, seed 2606).
- GREEN: generic suppression is now restricted to
  `CONNECTION_RELATIONSHIP_OMITTED`. The same run also fixes direct sibling
  publication, domain isolation, delegated early-return readers, rootless
  inverse fallbacks, and connection-qualified HABTM lookup as explicit
  regression seams (133 examples, 0 failures, seed 2606).

## Implementation review record

### Core round 1

- Architecture found one single-context diagnostic-byte regression and missing
  mixed sibling/domain-isolation/HABTM-consumer coverage.
- Rails found missing delegated-type early-return and rootless inverse fallback
  seams. Its proposed post-redaction de-duplication was not applied because the
  approved design intentionally preserves the number of distinct raw colliding
  contexts even when redaction collapses their public strings; the diagnostics
  schema does not require `uniqueItems`.

All actionable findings were repaired with the focused TDD cycle above.

### Core round 2

- Architecture: `指摘なし`.
- Rails / Active Record: `指摘なし`.

### Integrated matrix round 3

- Architecture required a closed success publication set, a missing
  outside-domain table to prove schema non-access, and missing collision tables
  to prove the fatal gate runs before probing.
- Rails independently identified the outside-domain schema-access seam.
- QA required fake-runner negative coverage for the entities, cross-domain
  runtime, and exact collision-diagnostics oracles.

The repair introduced an exact seven-file success publication set, removed the
outside-domain and collision tables while retaining their model declarations,
and added four negative verifier examples. RED was 8 examples / 2 failures
(seed 2607); after the validator and a schema-valid empty diagnostics fixture,
the same 8 examples passed.

### Integrated matrix round 4

- Architecture: `指摘なし`.
- Rails / Active Record: `指摘なし`.
- QA: `指摘なし`.

## Verification

- Full RSpec: 421 examples, 0 failures.
- Focused core/contracts: 177 examples, 0 failures (seed 2606).
- Focused P2-06 matrix negative cases: 8 examples, 0 failures (seed 2607).
- Real Rails matrix: every fixture family passes all three declared pairs,
  ending in `PASS 3/3 Rails matrix pairs`.
- RuboCop: 153 files, 0 offenses.
- Bundler Audit: advisory database updated, no vulnerabilities found.
- Undercover: no coverage missing in the latest changes.
