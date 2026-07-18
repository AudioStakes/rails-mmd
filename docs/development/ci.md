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

Use local hook output, not hosted GitHub Actions, as PR readiness evidence.
Dependency automation may cover Bundler through `.github/dependabot.yml`, but it
must not configure the `github-actions` package ecosystem.
