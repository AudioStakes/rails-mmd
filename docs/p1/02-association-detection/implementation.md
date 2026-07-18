# P1-02 Association Detection Implementation

Status: TDD implementation reviewed and verified

## TDD evidence

| Slice | Red | Green | Refactor |
|---|---|---|---|
| Matrix diagnostic oracle | Public matrix command passed when generated diagnostics were absent | Runner compares expected-code diagnostics with complete structured metadata | Unrelated P0 warning codes remain independently owned |
| All macro inventory | Real Rails 7.2 app failed because `Author.posts`, `profile`, and `tags` were silent | Rails 7.2 app published three `ASSOCIATION_MACRO_OMITTED` warnings and valid artifacts | One generic code plus macro metadata avoids per-macro code growth |
| Public builder behavior | New `RelationshipBuilder#build` example returned no warnings for three non-`belongs_to` reflections | One schema-valid warning per reflection; missing targets were never resolved | Primary and fallback reflection paths share classification |
| Stale harness contract | Full builder spec produced eight failures from `:belongs_to`-only doubles and silent-omission expectations | Doubles expose the all-reflection API and the obsolete expectation was replaced | Existing `belongs_to` behavior stayed isolated |
| Cross-component harness | Full repository gate found two schema-probe doubles still requiring the old macro argument | Schema-probe doubles now support Rails-compatible optional filtering and no-argument inventory | Shared test doubles mirror the public reflection surface |
| Closed macro metadata | With the macro shape deliberately loosened, missing, extra, and malformed fixtures were accepted | Restored required snake-case macro and closed properties; all three fixtures are rejected | Negative fixtures route through the shared schema contract spec |

## Verification evidence

- Relationship/schema/drift/matrix specs: 44 examples, 0 failures.
- Targeted RuboCop: 5 files, no offenses.
- Real Rails matrix: 3 pairs, 3 passes.
- Full default gate: RuboCop 68 files, RSpec 220 examples, bundler-audit,
  Undercover, and all 3 Rails matrix pairs passed.
- Repository hooks: pre-commit and forced pre-push passed.

## Implementation review record

| Round | Perspective | Findings | Correction |
|---|---|---|---|
| 1 | Rails 7.2/8.1 | None | — |
| 1 | Correctness / QA / TDD | None | — |
| 1 | Contract / architecture | Support matrix was stale; unit spec fixed internal order | Marked P1-02 supported; made builder assertion order-independent |
| 2 | Contract / architecture | None | — |
| 2 | Correctness / QA / TDD | None after cross-component harness repair | — |

## Residual risks

- The public warning identifies the macro but does not yet classify through,
  inverse, polymorphic inverse, or scope details.
- Rendering remains intentionally unchanged until P1-03–P1-07.
