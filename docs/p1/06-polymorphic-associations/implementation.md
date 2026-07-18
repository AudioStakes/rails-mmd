# P1-06 Polymorphic Associations Implementation

Status: TDD implementation reviewed and verified

## TDD evidence

| Slice | Red | Green | Refactor |
|---|---|---|---|
| Root and candidates | Polymorphic declarations emitted only generic omissions | Added one target-specific edge per matching inverse | Two-pass inventory isolates polymorphic resolution from direct edges |
| Duplicate target | Mixed inverse aliases could duplicate one target | Canonicalized by `has_one`, `has_many`, then lexical name | Candidate grouping is independent of reflection order |
| Holder keys | Only the id column was marked as FK | Projected both id and type columns | Public attribute schema remains unchanged |
| Failure paths | Missing candidates had no dedicated closed warning | Added unresolved-target warning and reused key warning | Association metadata shape stays closed and shared |
| Partial success | A conflicting inverse could hide valid candidates | Kept valid edges and diagnosed only the conflict | Candidate validation is per inverse |
| Deferred keys | Custom scalar id/type names were accepted beyond the design scope | Rejected non-default root key names with a polymorphic omission | Default-key eligibility is explicit and covered publicly |
| Rootless scope | Scoped inverse declarations without a root lost the scoped diagnostic | Preserved `ASSOCIATION_SCOPED_OMITTED` in the fallback | Every scoped polymorphic declaration follows one diagnostic rule |
| Real Rails | Matrix had no polymorphic association | Exact edge/group oracles pass all three supported pairs | Group oracle proves membership, root label, and both FK attributes |

## Verification evidence

- RelationshipBuilder specs: 37 examples, 0 failures.
- Full default gate: RuboCop 81 files, RSpec 252 examples, bundler-audit,
  Undercover, and all 3 Rails matrix pairs passed.
- Rails matrix: 3/3 pairs passed:
  Rails 7.2.3.1 / Ruby 4.0.6, Rails 8.1.3 / Ruby 3.3.12, and
  Rails 8.1.3 / Ruby 4.0.6.
- Repository hooks: pre-commit and pre-push passed.

## Implementation review record

| Round | Perspective | Findings | Correction |
|---|---|---|---|
| 1 | Rails runtime | Custom scalar polymorphic keys were accepted despite being deferred; omission table was stale | Added a default-key guard and synchronized the contract |
| 1 | Architecture | None | — |
| 1 | QA / TDD | New polymorphic group oracle lacked a task-level mismatch regression | Added a fake-artifact failure regression |
| 2 | Rails runtime | Rootless scoped inverse used a generic polymorphic warning | Preserved the scoped warning and added public Red/Green coverage |
| 2 | Architecture | None | — |
| 2 | QA / TDD | None | — |
| 3 | Rails runtime | Contract/design wording still narrowed scoped omissions to roots | Synchronized scoped inverse wording with runtime behavior |
| 3 | Architecture | None | — |
| 3 | QA / TDD | None | — |
| 4 | Rails runtime | None | — |

## Residual risks

- STI expansion, scoped and through polymorphism, `source_type:`, delegated
  types, and custom/composite keys remain deferred by the support matrix.
