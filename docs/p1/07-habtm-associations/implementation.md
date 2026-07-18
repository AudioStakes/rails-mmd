# P1-07 HABTM Associations Implementation

Status: TDD implementation reviewed and verified

## TDD evidence

| Slice | Red | Green | Refactor |
|---|---|---|---|
| Hidden join table | `DomainResult` exposed no HABTM table metadata | `SchemaProbe` caches normalized columns and primary key | Connection access remains isolated in `SchemaProbe` |
| Valid edge | HABTM reached the generic macro omission | Added one normalized `0..many` to `0..many` edge | Dedicated builder path precedes generic classification |
| Reciprocal and alias declarations | Equivalent declarations could duplicate or reorder output | Physical signature and canonical label emit one stable edge | Endpoint tuples and declaration winners are ordered lexically |
| Custom and self HABTM | Custom keys and self joins collided or omitted | Scalar custom table/keys and distinct self-join keys use the same path | Join-table identity owns both endpoint columns |
| Invalid table shape | Missing or malformed tables were silent or generic | Added a closed warning with five exact reason values | Validation is table-global; declaration failures remain local |
| Projection | Hidden join columns could be mistaken for endpoint FKs | IR contains no synthetic endpoint attributes | Join metadata never enters entity metadata |
| Real Rails | Matrix expected a macro warning | Reciprocal `Author.tags` / `Tag.authors` emits one exact edge | One fixture and oracle run on every declared pair |
| Probe failure containment | First unreadable owner could hide a readable reciprocal table | Probe retries validated entity models sharing the table | Grouping is deterministic by table name |

## Verification evidence

- SchemaProbe specs: 23 examples, 0 failures.
- Full default gate: RuboCop 82 files, RSpec 264 examples, bundler-audit,
  Undercover, and all 3 Rails matrix pairs passed.
- Exact Rails matrix: 3/3 pairs passed:
  Rails 7.2.3.1 / Ruby 4.0.6, Rails 8.1.3 / Ruby 3.3.12, and
  Rails 8.1.3 / Ruby 4.0.6.
- Repository hooks: pre-commit and pre-push passed.

## Implementation review record

| Round | Perspective | Findings | Correction |
|---|---|---|---|
| 1 | Rails runtime | None | — |
| 1 | Architecture | The first owner connection failure made shared join-table probing order-dependent | Retried every validated entity model for the grouped table and added a regression |
| 1 | QA / TDD | Implementation evidence was missing and the support matrix remained stale | Added this record and marked P1-07 supported |
| 2 | Rails runtime | None | — |
| 2 | Architecture | None | — |
| 2 | QA / TDD | None | — |

## Residual risks

- Payload-bearing join tables, scoped HABTM, composite/custom primary-key
  semantics, and cross-domain or multi-DB joins remain deferred by the support
  matrix.
