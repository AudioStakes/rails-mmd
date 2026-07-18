# P1-04 Inverse Canonical Edges Implementation

Status: TDD implementation reviewed and verified

## TDD evidence

| Slice | Red | Green | Refactor |
|---|---|---|---|
| Canonical ID/orientation | Paired and inverse-free edges retained declaration IDs/orientation | Every group uses physical ID and FK-holder orientation | Winner now supplies only label/macro |
| Label tie | Same-macro aliases could depend on reflection order | Macro priority plus lexical declaration ID selects one label | Grouping stays independent of Rails inverse inference |
| Inverse variants | Matrix lacked explicit, automatic, false, and paired self cases | Exact oracle covers all variants plus inverse-free direct | One physical grouping rule covers every case |
| Physical cardinality | Direct declaration cardinalities reversed with orientation | Group recomputes holder/reference bounds from semantic and DB evidence | Downstream schemas remain unchanged |

## Verification evidence

- RelationshipBuilder specs: 15 examples, 0 failures.
- Full default gate: RuboCop 72 files, RSpec 228 examples, bundler-audit,
  Undercover, and all 3 Rails matrix pairs passed.
- Repository hooks: pre-commit and forced pre-push passed.

## Implementation review record

| Round | Perspective | Findings | Correction |
|---|---|---|---|
| 1 | Rails runtime | Profile/Employee comments misclassified automatic/explicit inverse fixtures | Corrected fixture ownership comments |
| 1 | Architecture | Real alias case was missing; P1-03 contract winner text was stale | Added a same-FK `writer` alias and unified the active canonical contract |
| 1 | QA / TDD | Support state and final gate evidence were pending | Marked P1-04 supported; final verification remains below |
| 2 | Rails runtime | None | — |
| 2 | Architecture | None | — |
| 2 | QA / TDD | None | — |

## Residual risks

- Through, polymorphic, and HABTM relations require different physical identity
  dimensions and remain isolated to P1-05--P1-07.
