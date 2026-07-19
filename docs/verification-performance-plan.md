# Verification Performance Plan

Baseline measurements were taken on `origin/main` at
`1b978d93ad2880da7372b420382f143d89cbaa77` with Ruby 4.0.6 and Bundler
4.0.10.

## 優先1：Default gateのRails matrix二重実行を解消

Remove the duplicate real Rails matrix execution from the default gate while
preserving coverage of the Rake wiring and all three runtime pairs.

## 優先2：Rails matrix bundle cacheを再利用可能にする

Make the Rails matrix bundle cache deterministic and reusable for local and CI
verification, keyed by Ruby version and lockfile content.

## 優先3：Pre-commitのRSpec二重実行を解消

Prevent pre-commit from running the full RSpec suite twice when direct spec
routing and coverage-configuration routing overlap.

## 優先4：Contract suiteの二重実行を解消

Prevent the contract suite from running twice when schema-fixture and setup
drift routing overlap.

## Baseline

| Measurement | Cold cache | Warm cache |
|---|---:|---:|
| `bundle exec rake` | 59.657 s | 28.764 s |
| `bundle exec rake spec` / profiled RSpec | 48.355 s / 46.556 s | 18.514 s |
| `bundle exec rake verify:rails_matrix` | 39.292 s | 8.035 s |
| `bundle exec lefthook run pre-commit --all-files` | n/a | 50.060 s |

The cold profiled RSpec run spent 37.548 seconds in
`spec/integration/rails_matrix_task_spec.rb:224`, which executes all real
runtime pairs. The default Rake task then executes `verify:rails_matrix` again.

For pre-commit, `ruby-targeted-specs` took 17.739 seconds and
`rubocop-rspec-coverage-config` took 21.071 seconds. The two contract routing
jobs took 1.477 and 1.508 seconds.
