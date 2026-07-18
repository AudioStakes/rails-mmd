# P1-01 Runtime Compatibility Implementation

Status: TDD implementation in final verification

## TDD evidence

| Slice | Red | Green | Refactor |
|---|---|---|---|
| Package metadata | 2 failures for the Ruby range and direct Active Support dependency | Ruby `>= 3.3, < 4.1`; unused dependency removed | Package assertions moved to `spec/gem/specification_compatibility_spec.rb` |
| Missing Ruby | Public `verify:rails_matrix` command absent | Missing runtime reports the exact `asdf install ruby` command | Prerequisite checks isolated in the runner |
| Missing Bundler | Command did not validate per-Ruby Bundler | Missing Bundler reports the exact install command | Shared unbundled system boundary |
| Rails 8.1 app | Declared pair did not execute | Shared real app boots, loads schema, runs `rails-mmd generate`, and validates artifacts | Common app template and one Rails-series bundle |
| Rails 7.2 app | Frozen bundle absent | Same product path passes on Rails 7.2 | Per-series dependency data only |
| Artifact contracts | Parseable `{}` render plans were accepted | Existing render-plan and diagnostics schemas reject invalid artifacts | Reused `RailsMmd::SchemaValidator` |
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
  - 13 examples, 0 failures
- `ASDF_RUBY_VERSION=4.0.6 asdf exec bundle exec rake verify:rails_matrix`
  - `PASS ruby-4.0.6-rails-7.2`
  - `PASS ruby-3.3.12-rails-8.1`
  - `PASS ruby-4.0.6-rails-8.1`
  - `PASS 3/3 Rails matrix pairs`
- `ASDF_RUBY_VERSION=4.0.6 asdf exec bundle exec rake`
  - RuboCop: 68 files, no offenses
  - RSpec: 216 examples, 0 failures
  - bundler-audit: no vulnerabilities
  - undercover: no missing coverage in latest changes
  - Rails matrix: `PASS 3/3 Rails matrix pairs`
- Repository hooks: pending final staged run

## Implementation review record

| Round | Perspective | Findings | Correction |
|---|---|---|---|
| 1 | build engineering | `PASS 3/3` is hard-coded to `pairs.length` but aggregate count is not asserted for partial `RAILS_MMD_MATRIX_PAIR` selection; this is acceptable because partial mode is intentionally for diagnosis and uses an explicit selector match | No change; retain explicit selector behavior and keep summary as-is |
| 2 | self-review | Verification evidence incorrectly claimed the pre-push command had already been run | Replaced the claim with exact completed commands and kept repository hooks pending until the staged run finishes |
| 3 | docs review | README wording could be read as a 2×2 cross-product instead of three explicit pairs | Enumerated the three verified pairs explicitly |
| 4 | correctness review | None | No change |

## Residual risks

- The matrix proves only the three declared pairs, not every intermediate Ruby
  or future Rails patch.
- Rails 7.2 maintenance status remains controlled by Rails, not rails-mmd.
