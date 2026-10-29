# Git Hooks

This repository uses Bundler-managed Lefthook for local Git hooks.

Install hooks after `bundle install`:

```sh
ASDF_RUBY_VERSION=4.0.6 asdf exec bundle exec lefthook install
```

## Pre-Commit

The `pre-commit` hook passes staged paths to
`RailsMmd::VerificationRunner` in `tooling/verification_runner.rb`. Lefthook is
only the adapter; path classification, deduplication, and repair-first ordering
live behind the class's single `run!` interface.

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
read-only fallback tasks. Schema, fixture, and contract documentation paths run
`spec/contracts` for JSON schemas, schema fixtures, and repository drift guards.
When a staged `.mmd` fixture is included, that same RSpec invocation also runs
`spec/rails_mmd/mermaid_serializer_spec.rb` to compare actual serializer output
with the golden files.

When a repair command changes files, inspect the deterministic diff and stage
only the intended repairs before rerunning the hook. Do not rely on automatic
restaging.

## Pre-Push

The `pre-push` hook runs the CI-equivalent default Rake task:

```sh
ASDF_RUBY_VERSION=4.0.6 asdf exec bundle exec lefthook run pre-push --force
```

Use `--force` for manual verification so the hook executes even when there are
no commits to push. A manual invocation without it can be skipped by Lefthook.

Hosted GitHub Actions CI is intentionally disabled. Treat local `pre-push`
output as the final CI-equivalent evidence path for PR readiness.
