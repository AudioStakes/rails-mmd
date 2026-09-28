# Contributing

Thanks for helping improve rails-mmd. Please open an issue with a small reproduction before proposing a change to an output contract or a new association type. Include the Ruby and Rails versions, the relevant model declarations and schema, the command, expected output, and actual output. Remove credentials and private application details from reports and generated artifacts.

## Local setup

This is a standalone Ruby gem. Install the versions listed in `.ruby-version` and `fixtures/rails_matrix/matrix.yml` with asdf, then run:

```sh
bundle install
bundle exec lefthook install
bundle exec exe/rails-mmd --help
```

Use the repository's Ruby 4.0.6 for the root bundle. The Rails matrix also needs Ruby 3.3.12 and Bundler 4.0.10 for the selected pairs; see [the verification guide](docs/development/ci.md).

## Before a pull request

```sh
bundle exec rake rubocop
bundle exec rake spec
bundle exec rake
```

The default Rake task includes the Rails compatibility matrix and dependency audit. Local `pre-commit` and `pre-push` hooks are the final verification path described in [the hook guide](docs/development/hooks.md). Hosted GitHub Actions are intentionally disabled by the current repository policy, so include the commands and results you ran in the pull request.

Keep changes consistent with the [P0 contract](docs/p0-contract.md) and the [association support matrix](docs/active-record-association-support.md). Add a real-app matrix expectation when association behavior changes.
