# P2-01 Scoped Associations Implementation

Status: TDD implementation under specialist review correction

## TDD evidence

| Slice | Red | Green | Refactor |
|---|---|---|---|
| Direct `belongs_to` | Eligible scoped declarations emitted `ASSOCIATION_SCOPED_OMITTED` | One relationship carries `{ scoped: true }`; the raising proc is not called | Scope presence is observed only after existing structural gates |
| Direct `has_one` / `has_many` | Both declarations produced scoped omission warnings | Target-FK edges retain existing cardinality and scoped metadata | Both macros share the existing direct-has path |
| HABTM | A scoped alias produced no metadata | Canonical HABTM edges OR metadata across aliases | Join-table validation and identity are unchanged |
| Direct canonicalization | Winner order could discard a scoped declaration | Both declaration orders produce one scoped edge | Metadata merge is independent from label/cardinality selection |
| Through associations | Outer, source, and through-hop scopes were omitted or lost | Each actual scope proc contributes metadata after safe chain resolution | `has_scope?` is not used because it conflates `source_type` |
| Explicit through source | Scope and explicit-source failures shared a bundled regression | A dedicated public-seam case emits only `ASSOCIATION_MACRO_OMITTED` and no edge | Structural options remain ahead of scope observation |
| Through canonicalization | Same-path winner order could discard scope | Both declaration orders retain scoped metadata | The existing semantic-key winner remains unchanged |
| Polymorphic root and inverse | Supported scoped roots/inverses were omitted | Candidate-local edges retain root or matching-inverse scope | Two-pass inventory still never calls `klass` on a polymorphic `belongs_to` |
| Polymorphic structural failures | A rootless scoped inverse reported a scope omission | It remains `ASSOCIATION_POLYMORPHIC_OMITTED` | Scope cannot create an unresolved concrete target |
| Polymorphic canonicalization | Duplicate root order could discard scope | Root and inverse duplicate groups OR scoped metadata | All relationship kinds now use the same boolean merge rule |
| IR contract | Scoped metadata was absent and v1 relationships were closed | IR schema v2 accepts only `{ "scoped": true }` | Unscoped relationships omit `metadata` |
| Render-plan contract | ER/class plans discarded metadata | Both v2 plan variants project the normalized member | Arbitrary internal metadata cannot cross the public boundary |
| Invalid schema shapes | Null, empty, false, wrong-type, and extra members lacked coverage | IR and render-plan contract tests reject every closed-shape violation | Shared test literals keep both schemas aligned |
| Real Rails matrix | Exact oracle expected no scoped metadata | Raising scoped direct, through, HABTM, and polymorphic-inverse declarations publish exact metadata on all three pairs | Unscoped polymorphic and through edges retain observable optional-member absence |
| Matrix sensitivity | Removing metadata from the expected relationship was not observable | The task fails with `relationships did not match expectation` | The regression exercises the public Rake task |

## Verification evidence

- Relationship builder focused tests: scoped direct, through, HABTM, and
  polymorphic red/green slices passed, including both-order canonicalization.
- Full RSpec suite: 272 examples, 0 failures.
- Exact Rails matrix: 3/3 declared Ruby/Rails pairs passed.
- Default Rake gate: RuboCop inspected 82 files with no offenses; RSpec,
  bundler-audit, Undercover, and all matrix pairs passed.
- Repository hooks are pending the final reviewed snapshot.

## Implementation review record

| Round | Perspective | Findings | Correction |
|---|---|---|---|
| 1 | Rails runtime | Real matrix covered scoped `belongs_to` only, leaving real through, HABTM, and polymorphic reflection behavior unverified | Added raising scoped through, HABTM, and polymorphic inverse declarations with exact metadata oracles on every pair |
| 1 | Correctness / security | None | — |
| 1 | QA / TDD | No confirmed defect; recommended explicit unscoped-absence and closed-schema guards | Added IR/render-plan absence assertions; existing contract cases already reject null, empty, false, wrong-type, and extra-key metadata |
| 2 | Rails runtime | Pending | Pending |
| 2 | Correctness / security | Pending | Pending |
| 2 | QA / TDD | Pending | Pending |

## Residual risks

- Metadata intentionally records only scope presence. Scope source, proc text,
  SQL, and runtime predicates are neither exposed nor evaluated.
- Explicit `source`, typed/polymorphic through paths, custom primary keys,
  cross-domain edges, and behavioral association options remain assigned to
  later P2 items.
- IR and render-plan consumers must migrate to schema v2; configuration and
  diagnostics remain at v1.
