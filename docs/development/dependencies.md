# Dependency Classifications

`rails-mmd` keeps runtime dependencies in `rails-mmd.gemspec` and local
development/test tools in `Gemfile` development/test groups.

## Runtime

- `thor` provides the CLI.
- `json_schemer` validates configuration and artifact contracts.
- `json-canonicalization` supports deterministic artifact digests.

Active Support and Active Record come from the target Rails application bundle.
`rails-mmd` does not constrain their series in the gemspec; tested combinations
are listed in the [README](../../README.md).

## Development and test

- `rake`, `rspec`, `climate_control`
- `simplecov`, `undercover`
- `rubocop`, `rubocop-rspec`, `rubocop-rake`, `rubocop-performance`, `rubocop-packaging`
- `bundler-audit`, `lefthook`

## Dependency auditing

`bundle exec rake bundle:audit` checks both the root `Gemfile.lock` and every
`fixtures/rails_matrix/bundles/*/Gemfile.lock`. A vulnerable fixture dependency
fails the task and the default pre-push gate, even when the root bundle passes.
The audit runs from the root bundle and does not need the fixture applications
to boot. It reads the existing advisory database without updating it; refresh
that database explicitly with `bundle exec rake bundle:audit:update` before
checking newly published advisories.
