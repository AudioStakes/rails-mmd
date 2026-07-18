# Dependency Classifications

`rails-mmd` keeps runtime dependencies in `rails-mmd.gemspec` and local
development/test tools in `Gemfile` development/test groups.

## runtime-now

Runtime dependencies needed by the current CLI shell:

- `thor`: command-line shell for help and version behavior.

## future-p0-runtime-locked-now

Runtime dependencies locked now so future P0 runtime work can rely on them after
gem installation. These live in `rails-mmd.gemspec`, but help and version paths
must not load them until future issues need them:

- `json_schemer`
- `json-canonicalization`

Active Support and Active Record come from the target Rails application bundle.
`rails-mmd` must not constrain their series unless shipped code directly needs
an Active Support API.

## development-test

Development and test dependencies live only in `Gemfile` development/test groups
and must not be gemspec runtime dependencies:

- `rake`
- `rspec`
- `aruba`
- `climate_control`
- `simplecov`
- `undercover`
- `rubocop`
- `rubocop-rspec`
- `rubocop-rake`
- `rubocop-performance`
- `rubocop-packaging`
- `bundler-audit`
- `lefthook`
