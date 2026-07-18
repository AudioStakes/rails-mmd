# P1-01 Runtime Compatibility Implementation

Status: complete; reviewed with no remaining findings

## TDD evidence

| Slice | Red | Green | Refactor |
|---|---|---|---|
| Package metadata | 2 failures for the Ruby range and direct Active Support dependency | Ruby `>= 3.3, < 4.1`; unused dependency removed | Package assertions moved to `spec/gem/specification_compatibility_spec.rb` |
| Missing Ruby | Public `verify:rails_matrix` command absent | Missing runtime reports the exact `asdf install ruby` command | Prerequisite checks isolated in the runner |
| Missing Bundler | Command did not validate per-Ruby Bundler | Missing Bundler reports the exact install command | Shared unbundled system boundary |
| Rails 8.1 app | Declared pair did not execute | Shared real app boots, loads schema, runs `rails-mmd generate`, and validates artifacts | Common app template and one Rails-series bundle |
| Rails 7.2 app | Frozen bundle absent | Same product path passes on Rails 7.2 | Per-series dependency data only |
| Artifact contracts | Invalid plans and non-empty malformed Mermaid were accepted | Validate schemas and require Mermaid to match the serialized plan | Reused `SchemaValidator` and `MermaidSerializer` |
| Pair diagnosis | A selected pair required Rubies used only by other pairs | Check prerequisites for selected pairs only | Selection precedes prerequisite checks |
| Default gate | `default` omitted the matrix | `verify:rails_matrix` is a default prerequisite | Pre-push retains one entry point |
| Final three-pair scope | After reducing the matrix, the missing-Ruby assertion still assumed Ruby 3.3 was first | Three boundary pairs pass and report `PASS 3/3 Rails matrix pairs` | Manifest changed from Cartesian axes to explicit high-signal pairs |

The initial implementation explored all Rails 7.0–8.1/Ruby-boundary
combinations. Product scope was then reduced to Rails 7.2 and 8.1; unused
bundles were removed instead of preserving unclaimed compatibility fixtures.

## Final matrix

| Rails | Ruby | Result |
|---:|---:|---|
| 7.2.3.1 | 4.0.6 | PASS |
| 8.1.3 | 3.3.12 | PASS |
| 8.1.3 | 4.0.6 | PASS |

## Verification evidence

- `ASDF_RUBY_VERSION=4.0.6 asdf exec bundle exec rspec spec/gem/specification_compatibility_spec.rb spec/integration/rails_matrix_task_spec.rb spec/rake/task_spec.rb`
  - 15 examples, 0 failures
- `ASDF_RUBY_VERSION=4.0.6 asdf exec bundle exec rake verify:rails_matrix`
  - `PASS ruby-4.0.6-rails-7.2`
  - `PASS ruby-3.3.12-rails-8.1`
  - `PASS ruby-4.0.6-rails-8.1`
  - `PASS 3/3 Rails matrix pairs`
- `ASDF_RUBY_VERSION=4.0.6 asdf exec bundle exec rake`
  - RuboCop: 68 files, no offenses
  - RSpec: 218 examples, 0 failures
  - bundler-audit: no vulnerabilities
  - undercover: no missing coverage in latest changes
  - Rails matrix: `PASS 3/3 Rails matrix pairs`
- Repository hooks: pre-commit and forced pre-push passed on the staged change

## Implementation review record

| Round | Perspective | Findings | Correction |
|---|---|---|---|
| 1 | Rails runtime | Selected diagnosis required all Rubies; Mermaid check accepted malformed text; manifest duplicated an unused patch version | Scoped prerequisites to selected pairs, compared Mermaid to the validated plan, and made bundle Gemfiles the single patch-version owner |
| 1 | build engineering | None | No change |
| 1 | correctness | Verification counts drifted after adding review regressions | Updated evidence to the fresh 15/218-example runs |
| 2 | Rails runtime | None | No change |
| 2 | correctness | None | No change |

## Residual risks

- The matrix proves only the three declared pairs, not every intermediate Ruby
  or future Rails patch.
- Rails 7.2 maintenance status remains controlled by Rails, not rails-mmd.
