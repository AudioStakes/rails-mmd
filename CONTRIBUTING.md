# Contributing

Thanks for helping improve rails-mmd. For help using the CLI, start with the [README](README.md). To report a bug or propose a feature, [open an issue](https://github.com/AudioStakes/rails-mmd/issues/new/choose). Please discuss changes to an output contract or a new association type in an issue before implementing them. Documentation corrections can go directly to a pull request.

Include a small reproduction with the rails-mmd, Ruby and Rails versions, database adapter, relevant model declarations and schema, command, expected output, and actual output. Remove credentials and private application details from reports and generated artifacts. For suspected vulnerabilities, follow the [security policy](SECURITY.md).

## Local setup

This is a standalone Ruby gem. You need Git, asdf with its Ruby plugin, and the platform build tools needed to install Ruby and native gems. The root development bundle uses Ruby 4.0.6 and Bundler 4.0.10. The full verification matrix also needs Ruby 3.3.12. Network access is needed to install gems and obtain dependency advisories. You do not need a separate Rails application for the test suite; it creates disposable SQLite fixture applications.

Fork the repository on GitHub, then clone your fork (replace `YOUR-USERNAME`):

```sh
git clone https://github.com/YOUR-USERNAME/rails-mmd.git
cd rails-mmd
git remote add upstream https://github.com/AudioStakes/rails-mmd.git
git switch -c your-change
```

Install the pinned Ruby versions and Bundler:

```sh
asdf install ruby 4.0.6
asdf install ruby 3.3.12
ASDF_RUBY_VERSION=4.0.6 asdf exec gem install bundler -v 4.0.10
ASDF_RUBY_VERSION=3.3.12 asdf exec gem install bundler -v 4.0.10
```

Select the root Ruby in this shell, install the development bundle, and enable hooks:

```sh
export ASDF_RUBY_VERSION=4.0.6
asdf exec bundle install
asdf exec bundle exec lefthook install
asdf exec bundle exec exe/rails-mmd --help
```

Set `ASDF_RUBY_VERSION=4.0.6` again in each new shell used for development or Git hooks. These commands select Ruby explicitly and do not depend on asdf recognizing `.ruby-version`. For matrix prerequisites and cache behavior, see [the verification guide](docs/development/ci.md).

## Before a pull request

```sh
asdf exec bundle exec rake rubocop:auto_correct
asdf exec bundle exec rake spec
```

Inspect any autocorrections and stage only your intended changes. Committing runs the `pre-commit` hook; pushing runs `pre-push`. You can run the full gate before pushing:

```sh
asdf exec bundle exec lefthook run pre-push --force
```

Use `--force` for a manual run so Lefthook executes the gate even when there are no commits to push.

The gate includes lint, specs, coverage, dependency audit, and the Rails compatibility matrix. The first matrix run installs its own locked bundles and can take longer than subsequent runs. Local hooks are the final verification path described in [the hook guide](docs/development/hooks.md). Hosted GitHub Actions are intentionally disabled by the current repository policy, so include the commands and results you ran in the pull request. Passing checks are evidence from the contributor's machine; there is no hosted CI badge or check to wait for.

Push your branch to your fork and open a pull request against `AudioStakes/rails-mmd`'s `main` branch. Explain the problem, resulting behavior, and any limitations. Keep unrelated changes out of the pull request.

Keep changes consistent with the [P0 contract](docs/p0-contract.md) and the [association support matrix](docs/active-record-association-support.md). Add a real-app matrix expectation when association behavior changes.

## Releases

Maintainers publish releases manually from a verified commit on `main`. Follow the [release guide](docs/development/releasing.md) for package inspection, publishing, and recovery, and record user-facing changes in [CHANGELOG.md](CHANGELOG.md).

## When setup or checks fail

- Wrong Ruby or Bundler version: check `asdf exec ruby --version` and `asdf exec bundle --version` after selecting `ASDF_RUBY_VERSION=4.0.6`. Install both matrix Rubies and their pinned Bundler versions before running the full gate.
- Dependency advisory data unavailable: with network access, run `asdf exec bundle exec rake bundle:audit:update`, then rerun the hook.
- A hook changes files or rejects partially staged files: inspect the diff, stage the intended repairs, and rerun it; see the [repair-first workflow](docs/development/hooks.md).
- Coverage cannot resolve `HEAD~1`: use a normal clone with Git history, rather than a shallow one. See [tooling commands](docs/development/tooling.md) to choose a comparison base deliberately.
- A Rails matrix pair fails: use the single-pair command in the [verification guide](docs/development/ci.md) for diagnosis, then rerun the full hook after repairing it.
