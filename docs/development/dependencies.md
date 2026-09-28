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

- `rake`, `rspec`, `aruba`, `climate_control`
- `simplecov`, `undercover`
- `rubocop`, `rubocop-rspec`, `rubocop-rake`, `rubocop-performance`, `rubocop-packaging`
- `bundler-audit`, `lefthook`
