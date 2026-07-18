# P2-03 Delegated Type Implementation

Status: complete

## Baseline

- Stack base: `codex/p2-02-sti`
- Research commit: `0326e23`
- Design commit: `d2cc675`
- Contract: `research.md` and `design.md`
- Method: public-seam TDD, one observed red before each minimum green change

## Phase gates

| Phase | Specialist perspectives | Review result |
|---|---|---|
| Research | Rails runtime, architecture, QA / compatibility | Round 3: no findings |
| Design | Rails runtime, internal API, QA / TDD | Round 3: no findings |
| Implementation | Rails runtime, correctness / contract, QA / TDD | Round 2: no findings |

## Planned TDD slices

| Slice | Public seam | Required red |
|---|---|---|
| Domain ownership | `DomainResolver#resolve` | All-configured-domain ownership and exact exclusion intent are absent |
| Generation handoff | `Generate#call` | `SchemaProbe#probe` does not receive ownership metadata |
| Family expansion | `SchemaProbe#probe` | Selecting a delegator does not add eligible declared physical targets |
| Provenance and guards | `SchemaProbe#probe` | Spoof, exclusion, domain, connection, renderability, and failed-probe outcomes are not closed |
| Whitelist edges | `RelationshipBuilder#build` | No-inverse declared types do not publish; undeclared inverses can publish |
| Origin and inverse evidence | `RelationshipBuilder#build` | Expanded owners leak unrelated associations; optional inverse/cardinality/scope behavior is incomplete |
| Exact diagnostics | `RelationshipBuilder#build` | Target omissions and the single zero-target warning are incomplete or unstable |
| Real Rails matrix | `verify:rails_matrix` | No delegated runtime/family/oracle coverage exists on the declared pairs |

## TDD execution record

- Domain/Generate seam: RED `19 examples, 6 failures`; GREEN `19 examples, 0 failures`.
- SchemaProbe seam: RED rejected `owned_domain_ids_by_constant`, lacked family
  records, and did not expand targets; GREEN `30 examples, 0 failures`.
- RelationshipBuilder seam: RED published an undeclared inverse and omitted a
  declared no-inverse target; GREEN `51 examples, 0 failures`.
- Matrix family execution: RED ran only the default fixture; GREEN runs
  `default` and `delegated_type` for every selected pair.
- Harness isolation: RED leaked `RAILS_MMD_MATRIX_FIXTURE_FAMILY` into the Rails
  process and altered redaction; GREEN explicitly removes both matrix selectors.
- Delegated runtime oracle: RED accepted missing, malformed, and mismatched
  evidence; GREEN rejects all three and validates exact runtime provenance.
- Rails 8.1 / Ruby 4.0.6 real-app slice: GREEN with exact relationship,
  polymorphic-group, diagnostic, ER, class, STI, and delegated runtime oracles.

## Implementation review record

| Round | Perspective | Finding | Correction |
|---|---|---|---|
| 1 | Rails runtime, correctness / contract | Declared invalid inverses could escape the family path, lose target-specific diagnostics, and fall through as leftovers | Mark inventory inverses handled immediately; diagnose unresolved and wrong-owner inverses inside the family while preserving declared edges |
| 1 | Correctness / contract | Failed expanded-target schema diagnostics followed selected-owner traversal order | Sort delegated expansion diagnostics by target constant, code, and subject after family construction; added reversed-order regression |
| 1 | QA / TDD | Structural delegated-root short-circuit lacked a direct regression | Added a sole-root-diagnostic test proving no target diagnostics, zero-target warning, or edge leaks |
| 1 | QA / TDD | Suggested public diagnostic-oracle order differed from builder append order | Verified all six real matrix executions; retained the actual canonically published diagnostic order while keeping builder append order unit-covered |
| 2 | Rails runtime, correctness / contract, QA / TDD | No findings | None |

## Verification evidence

- Combined DomainResolver, Generate, and RelationshipBuilder specs:
  `70 examples, 0 failures`; six owned files had no RuboCop offenses.
- SchemaProbe owned spec: `30 examples, 0 failures`; two owned files had no
  RuboCop offenses.
- Delegated runtime-oracle regressions: `3 examples, 0 failures`.
- Combined delegated implementation and matrix specs: `129 examples, 0 failures`.
- RelationshipBuilder and SchemaProbe after review fixes: `84 examples, 0 failures`.
- Matrix harness spec: `29 examples, 0 failures`.
- All configured real-Rails executions passed: three explicit Ruby/Rails pairs
  multiplied by `default` and `delegated_type` fixture families (six runs).
- Final default Rake gate: `109 files inspected, no offenses detected`;
  `317 examples, 0 failures`; Bundler Audit found no vulnerabilities;
  Undercover reported no missing coverage; all six real matrix executions passed.
- Direct pre-commit and pre-push hook evidence is recorded in the final branch
  commit/PR handoff.
