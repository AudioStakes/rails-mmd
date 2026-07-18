# P1-05 Through Associations Implementation

Status: TDD implementation reviewed and verified

## TDD evidence

| Slice | Red | Green | Refactor |
|---|---|---|---|
| Simple `has_many :through` | No semantic edge or relationship kind existed | Added owner-to-target semantic edge beside direct physical edges | Through identity is isolated from physical FK identity |
| `has_one` and nested paths | No singular bound or full path existed | Added macro-specific target bound and owner-forward full chain | One builder handles one-hop and nested paths |
| Duplicate paths | Identical paths could emit twice | Grouped by owner, normalized path, and final target | Existing macro/lexical priority selects the canonical label |
| Failure paths | Missing through/source codes were outside the closed catalog | Added two schema-closed warnings and per-hop eligibility checks | Existing association metadata shape is reused |
| Rails reflection failures | `has_scope?` exceptions escaped and nested source options were hidden from join-chain hops | Resolve through/source first, traverse source lineage, and downgrade reflection failures | Option classification now precedes scope evaluation |
| Real Rails | Matrix did not contain through declarations | Exact oracle covers one-hop, singular, nested, and distinct paths | Same fixture passes all 3 supported pairs |

## Verification evidence

- RelationshipBuilder specs: 28 examples, 0 failures.
- Diagnostic schema/primitives specs: 26 examples, 0 failures.
- Full default gate: RuboCop 79 files, RSpec 240 examples, bundler-audit,
  Undercover, and all 3 Rails matrix pairs passed.
- Repository hooks: pre-commit and pre-push passed.
- Rails matrix: 3/3 pairs passed:
  Rails 7.2.3.1 / Ruby 4.0.6, Rails 8.1.3 / Ruby 3.3.12, and
  Rails 8.1.3 / Ruby 4.0.6.

## Implementation review record

| Round | Perspective | Findings | Correction |
|---|---|---|---|
| 1 | Rails runtime | Nested inner `source:` / `source_type:` were not visible on flattened join-chain hops | Traverse nested `source_reflection` lineage and test explicit/typed inner sources |
| 1 | Architecture | `has_scope?` could raise before resolution; ID ended in the outer declaration name | Resolve first, contain scope failures, and use terminal source name in IDs |
| 1 | QA / TDD | Resolved non-renderable/domain and unreadable-chain failure paths lacked through regressions | Added public regression tests for both boundaries |
| 2 | Rails runtime | None | — |
| 2 | Architecture | None | — |
| 2 | QA / TDD | None | — |
| 3 | Architecture | Same-macro same-path label tie still fell back to reflection order | Added lexical association-name tie-break and reverse-order regression |
| 4 | Architecture | None | — |

## Residual risks

- Explicit `source:` / `source_type:`, scoped through paths, and polymorphic
  paths remain deferred by the support matrix.
