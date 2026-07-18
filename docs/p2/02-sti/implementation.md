# P2-02 Single-Table Inheritance Implementation

Status: implementation and specialist review complete; final repository gate pending

## Baseline

- Stack base: `codex/p2-01-scoped-associations`
- Research/design commit: `11370b2`
- Contract: `docs/p2/02-sti/research.md` and `design.md`
- Method: public-seam TDD, one observed red before each minimum green change

## Phase gates

| Phase | Specialist perspectives | Review result |
|---|---|---|
| Research | Rails runtime, architecture, QA / compatibility | Round 2 and exact-final Round 3: no findings |
| Design | Rails runtime, API / contract, QA / TDD | Round 4: no findings |
| Implementation | Rails runtime, correctness / contract, QA / TDD | Round 4: no findings |

## TDD execution record

| Slice | Public seam | Red evidence | Green evidence | Result |
|---|---|---|---|---|
| Git environment isolation | `HookChecks` temporary-repository specs | `asdf exec bundle exec rspec spec/rails_mmd/hook_checks_spec.rb -e 'isolates nested repository environment when building temporary repos'` failed at `git add example.rb` with inherited repository variables | Full file: 14 examples, 0 failures; RuboCop: 1 file, no offenses | Complete |
| STI normalization | `SchemaProbe#probe` | Focused direct/multi-level spec failed with `unknown keyword: :inventory_records` | SchemaProbe + Generate: 40 examples, 0 failures; RuboCop: 4 files, no offenses | Complete |
| Generation handoff | `Generate#call` | Focused spec showed `SchemaProbe#probe` received only `domains` | Included in 40-example green suite above | Complete |
| IR v3 | `IrBuilder#build` and IR schema | Focused spec expected version 3 and received 2 | IR/RenderPlan/contracts: 46 examples, 0 failures; RuboCop: 5 files, no offenses | Complete |
| Render plan v3 | `RenderPlanBuilder#build` and render-plan schema | Focused class and ER specs expected version 3 and received 2; invalid subtype-attribute and malformed-label fixtures were initially accepted | Contract suite: 14 examples, 0 failures after closed conditional rules | Complete |
| Mermaid inheritance | `MermaidSerializer#serialize` | Golden diff lacked FQ subtype label and inheritance line | Serializer: 12 examples, 0 failures; RuboCop: 2 files, no offenses | Complete |
| Real Rails matrix | `verify:rails_matrix` | Missing/mismatched class/ER Mermaid, STI node, inheritance, and runtime oracle mutations failed their focused integration examples | Rails matrix: PASS 3/3; integration: 21 examples, 0 failures; tooling/fixture RuboCop: no offenses | Complete |
| STI graph integrity | `IrBuilder#build` | A deliberately cyclic pair of subtype parents was accepted | Added deterministic cycle validation; IR builder + matrix integration suite: 29 examples, 0 failures | Complete |
| Exact diagnostic oracle | `ArtifactValidator` | An unexpected diagnostic passed when the expected diagnostic list was empty | Removed code filtering and checked the complete normalized diagnostic projection; all real matrix pairs pass with an explicit 12-record expectation | Complete |
| Expected JSON failure boundary | `ArtifactValidator` | A missing checked-in STI JSON oracle escaped as raw `Errno::ENOENT` | All expected JSON reads now normalize missing and malformed files to `VerificationError`; focused regression: 1 example, 0 failures; RuboCop: 2 files, no offenses | Complete |
| Defensive branch coverage | `IrBuilder#build` and `RenderPlanBuilder#build` | Undercover identified unexecuted invalid-record and missing/duplicate-token guards | Added public-boundary invalid-input specs without implementation changes; coverage gate: 296 examples, 0 failures; Undercover: no missing coverage | Complete |
| Regression closure | public contract and selection specs | Invalid subtype attributes and malformed FQ labels were initially schema-valid; abstract-family and exact-oracle audits found observable gaps | Closed schemas, explicit post-abstract family, exact renderer/runtime projections, graph validation, and deterministic oracle failures are covered | Complete |

## Implementation contribution record

| Perspective | Ownership |
|---|---|
| Test automation / tooling | Inherited Git environment reproduction, isolation helper, and durable repository rule |
| Rails runtime | Inventory-bounded STI normalization and generation handoff |
| Contract implementation | Closed IR/render-plan v3 schemas, projections, and invalid-reference seams |
| Integration | Serializer, exact Mermaid oracles, real Rails matrix, migration docs, and final gate |

## Implementation review record

| Round | Perspective | Findings | Correction |
|---|---|---|---|
| Pre-review audit | Rails runtime | The initial abstract-intermediate double kept the old base class, which real Rails does not: a concrete class below an abstract superclass begins a new `base_class` family | Corrected research, design, and unit expectations; the real matrix treats the abstract boundary as a negative family instead of reattaching it |
| Design correction review | QA / compatibility | The matrix plan proved exclusion from the earlier family but did not explicitly select and verify the new post-boundary concrete family | Required both bases in matrix config and exact subtype/inheritance oracles for the post-boundary family |
| Integration audit | Contract / matrix | IR-only `inheritance_column` and `sti_name` cannot be compared from the intentionally metadata-free render plan | Split the real-app oracle into renderer node/edge projections and a fixture-owned Rails runtime metadata projection; no IR publication or render-plan metadata was added |
| Implementation Round 1 | Rails runtime | Diagnostic comparison filtered actual records to only codes named by the expectation, so an empty expectation ignored every unexpected diagnostic | Compare the complete normalized diagnostic list and check in the exact real-app expectation |
| Implementation Round 1 | QA / TDD | IR parent references were validated, but a cyclic STI inheritance graph was not rejected | Added a failing cyclic-parent example and deterministic cycle validation |
| Implementation Round 1 | Correctness / contract | No findings | None |
| Implementation Round 2 | Correctness / contract | Missing or malformed expected JSON oracles leaked raw filesystem/parser exceptions | Added a failing missing-oracle integration example and a shared controlled read boundary for every expected JSON oracle |
| Implementation Round 2 | Rails runtime, QA / TDD | No findings | None |
| Implementation Round 3 | Rails runtime, correctness / contract, QA / TDD | No findings | None |
| Implementation Round 4 | Rails runtime, correctness / contract, QA / TDD | No findings after defensive-branch coverage additions | None |

## Verification evidence

- RuboCop: 99 files inspected, no offenses before the final coverage additions; focused changed specs remain clean.
- RSpec coverage gate: 296 examples, 0 failures.
- Undercover: no coverage missing in the P2-02 changes.
- Bundler Audit: no vulnerabilities found before the final coverage additions.
- The complete default gate and direct Git hooks are rerun after the final documentation/test commit.
