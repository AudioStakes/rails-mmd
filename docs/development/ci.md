# Continuous Integration

Hosted GitHub Actions CI is intentionally disabled for this repository. Do not
add tracked `.github/workflows/*.yml` or `.github/workflows/*.yaml` files.

The local Lefthook `pre-push` hook is the CI-equivalent verification gate:

```sh
ASDF_RUBY_VERSION=4.0.5 asdf exec bundle exec lefthook run pre-push
```

`pre-push` runs the default Rake verification contract:

```sh
ASDF_RUBY_VERSION=4.0.5 asdf exec bundle exec rake
```

Use local hook output, not hosted GitHub Actions, as PR readiness evidence.
Dependency automation may cover Bundler through `.github/dependabot.yml`, but it
must not configure the `github-actions` package ecosystem.
