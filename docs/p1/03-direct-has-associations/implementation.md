# P1-03 Direct Has Associations Implementation

Status: TDD implementation reviewed and verified

## TDD evidence

| Slice | Red | Green | Refactor |
|---|---|---|---|
| Direct has edges | Direct `has_many` / `has_one` returned macro omission warnings | Builder emits declaration-oriented edges from target-side FK evidence | Separate direct key projection from `belongs_to` keys |
| FK attribute holder | `Relationship` had no target-side holder and IR could not mark the FK | Explicit holder ID/column projects the FK on the actual entity | Public IR schema remains unchanged |
| Unsupported variants | Direct classification could resolve through/scope/`as:` targets | Ordered guards preserve generic, scoped, and polymorphic omission paths | Existing public diagnostic codes are reused |
| Key reader failure | A raising direct `foreign_key` reader was misreported as target unresolved | Key-reader failures degrade to composite-key omission without masking resolved targets | Rescue boundary follows the failed phase |
| Provisional duplicate | Paired `belongs_to` / `has_many` produced two physical edges | Existing `belongs_to` wins the physical tuple | P1-04 retains inverse-aware reconciliation ownership |
| Real relationship oracle | Matrix passed with no expected relationship comparison | Exact relationship projection is versioned and checked | Diagnostics and relationships remain separate oracles |

## Verification evidence

- Relationship and IR specs: 16 examples, 0 failures.
- Full RSpec: 227 examples, 0 failures.
- Full default gate: RuboCop 71 files, RSpec 227 examples, bundler-audit,
  Undercover, and all 3 Rails matrix pairs passed.
- Targeted RuboCop: 6 implementation/spec files, no offenses.
- Repository hooks: pre-commit and forced pre-push passed.

## Implementation review record

| Round | Perspective | Findings | Correction |
|---|---|---|---|
| 1 | Rails runtime | Direct key-reader errors were collapsed into target resolution and untested | Narrowed the rescue boundary and added a public regression example |
| 1 | Architecture | Support matrix was stale; exception contract was broader than implementation | Marked P1-03 supported and made target/key failure mapping explicit |
| 1 | QA / TDD | Support/status and final gates were pending | Updated product state; final evidence remains below |
| 2 | Rails runtime | None | — |
| 2 | Architecture | None | — |
| 2 | QA / TDD | None | — |

## Residual risks

- Physical-key suppression intentionally preserves the `belongs_to` label;
  P1-04 owns semantic inverse pairing and canonical label policy.
- `has_one` is diagrammed as singular from the Active Record macro even when a
  unique database constraint is absent.
