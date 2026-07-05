# Git Hooks

This repository uses Bundler-managed Lefthook for local Git hooks.

Install hooks after `bundle install`:

```sh
ASDF_RUBY_VERSION=4.0.5 asdf exec bundle exec lefthook install
```

## Pre-Commit

The `pre-commit` hook is repair-first and sequential.

For Ruby-like staged files, it runs:

1. staged safety check
2. RuboCop autocorrect
3. post-repair tracked-diff check
4. read-only RuboCop diagnostics
5. direct spec files when staged specs are present

The staged safety check fails before repair when a tracked file has both staged
and unstaged changes. The post-repair check fails when autocorrect changes a
tracked file, and the hook does not run `git add` or enable Lefthook
`stage_fixed`.

Dependency/setup files have their own route. `Gemfile`, `Gemfile.lock`, and
`*.gemspec` run `bundle check` and Bundler Audit. `.ruby-version` runs only Ruby
and CLI version smoke checks.

RuboCop, RSpec, SimpleCov, and Undercover config files run the relevant
read-only fallback tasks. Schema and fixture globs are intentionally inert until
the schema/fixture specs exist; they print compact routing output and do not run
unrelated checks.

## Pre-Push

The `pre-push` hook runs the CI-equivalent default Rake task:

```sh
ASDF_RUBY_VERSION=4.0.5 asdf exec bundle exec lefthook run pre-push
```

GitHub Actions runs the same default Rake verification contract.
