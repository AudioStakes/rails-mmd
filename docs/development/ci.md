# Continuous Integration

GitHub Actions runs the same default Rake verification contract as the local
Lefthook `pre-push` hook:

```sh
ASDF_RUBY_VERSION=4.0.5 asdf exec bundle exec rake
```

The workflow is read-only. It does not run RuboCop autocorrect and does not use
Node, TypeScript, or Node package-manager tooling.

Dependency automation covers Bundler and GitHub Actions workflow dependencies
through `.github/dependabot.yml`. It does not configure Node ecosystem updates.
