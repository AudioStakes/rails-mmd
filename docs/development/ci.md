# Continuous Integration

Hosted GitHub Actions CI is intentionally disabled for this repository. Do not
add tracked `.github/workflows/*.yml` or `.github/workflows/*.yaml` files.

The local Lefthook `pre-push` hook is the CI-equivalent verification gate:

```sh
ASDF_RUBY_VERSION=4.0.6 asdf exec bundle exec lefthook run pre-push
```

`pre-push` runs the default Rake verification contract:

```sh
ASDF_RUBY_VERSION=4.0.6 asdf exec bundle exec rake
```

The default task includes the real-app Rails matrix. Install its Ruby and
Bundler prerequisites once:

```sh
asdf install ruby 3.3.12
asdf install ruby 4.0.6
ASDF_RUBY_VERSION=3.3.12 asdf exec gem install bundler -v 4.0.10
ASDF_RUBY_VERSION=4.0.6 asdf exec gem install bundler -v 4.0.10
```

For diagnosis, run one pair without weakening the pre-push gate:

```sh
RAILS_MMD_MATRIX_PAIR=ruby-4.0.6-rails-8.1 \
  ASDF_RUBY_VERSION=4.0.6 asdf exec bundle exec rake verify:rails_matrix
```

Matrix gems default to a repository-local, Git-ignored cache keyed by Ruby
version, Rails series, and the selected `Gemfile.lock` SHA-256. To reuse that
cache across worktrees or external CI jobs, restore one stable directory and
set it explicitly:

```sh
RAILS_MMD_MATRIX_CACHE_ROOT=/stable/cache/rails-mmd-matrix \
  ASDF_RUBY_VERSION=4.0.6 asdf exec bundle exec rake verify:rails_matrix
```

Keep the absolute cache root stable when native extensions are present. Treat
the cache as restore-only across worktrees or CI jobs: populate it from one
trusted writer, restore only from owner-controlled cache keys, and give each job
an owner-controlled writable root. Do not share a writable digest directory
across concurrent jobs or trust boundaries. If parallel jobs need the same warm
cache, restore it into separate job-local paths. Hosted GitHub Actions remain
disabled; this variable is an integration seam for trusted local or external CI
environments.

Use local hook output, not hosted GitHub Actions, as PR readiness evidence.
Dependency automation may cover Bundler through `.github/dependabot.yml`, but it
must not configure the `github-actions` package ecosystem.
