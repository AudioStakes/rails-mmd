# Releasing rails-mmd

Maintainers build with the tasks provided by `bundler/gem_tasks` in the root Rakefile, then publish the verified archive manually to [RubyGems.org](https://rubygems.org/gems/rails-mmd). Hosted GitHub Actions are intentionally disabled; there is no automatic publishing workflow.

## Prepare and verify

1. Follow [CONTRIBUTING.md](../../CONTRIBUTING.md) to install the development and matrix prerequisites and local hooks. Set `ASDF_RUBY_VERSION=4.0.6` in the release shell.
2. Set the release version in `lib/rails_mmd/version.rb` and update [CHANGELOG.md](../../CHANGELOG.md). Review the gemspec's dependencies, packaged files, and metadata. Commit the preparation through the local `pre-commit` hook and merge it to `main`.
3. Use a clean checkout of that `main` commit, synchronized with the authoritative `origin` at `AudioStakes/rails-mmd`. Check tracked and untracked files with `git status --short --untracked-files=all`. Confirm that the version is not already published and the version tag does not already exist locally or on `origin`.
4. Run both local verification gates from the release checkout:

   ```sh
   export ASDF_RUBY_VERSION=4.0.6
   asdf exec bundle install
   asdf exec bundle exec lefthook run pre-commit --all-files --force
   asdf exec bundle exec lefthook run pre-push --force
   ```

   If a check repairs files, inspect and commit the intended repairs through the normal review flow, then verify the resulting release commit again. The [hook guide](hooks.md) describes the repair-first contract.

5. Use a RubyGems.org account authorized to publish `rails-mmd`, with multi-factor authentication enabled. Sign in interactively in your own terminal if needed:

   ```sh
   asdf exec gem signin --host https://rubygems.org
   ```

   Follow the [RubyGems publishing guide](https://guides.rubygems.org/publishing/) and [MFA guide](https://guides.rubygems.org/using-mfa-in-command-line/). Enter credentials and MFA responses only at the interactive prompts; never put them in repository files, command arguments, logs, or chat. The gemspec requires MFA for publishing. For the first release, verify that the name is still available immediately before publishing.

## Inspect and publish

The commands below use the initial version, `0.1.0`; replace it for later releases. Fix the build timestamp to the verified commit for reproducible builds:

```sh
export SOURCE_DATE_EPOCH="$(git show -s --format=%ct HEAD)"
asdf exec bundle exec rake build:checksum
asdf exec gem specification pkg/rails-mmd-0.1.0.gem
shasum -a 256 pkg/rails-mmd-0.1.0.gem
```

`build:checksum` runs `build`, writes `pkg/rails-mmd-0.1.0.gem`, and writes its SHA-512 digest to `checksums/rails-mmd-0.1.0.gem.sha512`. Inspect the packaged files and metadata, and retain a copy of the reviewed `.gem`, both digests, the commit SHA, and verification results in release records outside the checkout. Move the generated checksum out of the checkout as well, and confirm the checkout is clean before release. Do not modify the verified source or rebuild the archive between inspection and publishing.

Tag the verified `main` commit, push only that tag, and upload the inspected archive:

```sh
git tag -a v0.1.0 -m 'rails-mmd 0.1.0'
git push origin refs/tags/v0.1.0
asdf exec gem push --host https://rubygems.org pkg/rails-mmd-0.1.0.gem
```

The push can prompt for MFA. Keep the command output with the release evidence. Bundler also provides `rake release[origin]`, but it rebuilds the gem and pushes the current branch and tags before uploading; the explicit commands above keep publication tied to the archive already inspected.

## Confirm publication

Check the version-specific registry response:

```sh
curl --fail --silent --show-error \
  https://rubygems.org/api/v2/rubygems/rails-mmd/versions/0.1.0.json \
  | jq '{name, version, sha, source_code_uri, changelog_uri}'
```

Confirm version `0.1.0`, compare the registry's `sha` with the recorded SHA-256, and verify that `v0.1.0` points to the release commit on GitHub. In a separate directory and a clean Ruby environment, install the published gem and check its executable:

```sh
gem install rails-mmd --version 0.1.0 --no-document
rails-mmd --version
rails-mmd generate --help
```

The version command must print `0.1.0`. Then use the [README quick start](../../README.md#try-it-in-a-rails-app) in a Rails application with the RubyGems dependency to confirm generation. Record the result with the release evidence.

## Resume after a failure

Git tag publication and RubyGems publication are separate operations. If either push fails or the result is uncertain, inspect the remote tag and the version-specific RubyGems API before retrying. An HTTP 404 means the version was not found; a network error is inconclusive.

If the version exists, compare its SHA-256 with the retained artifact and complete the installation check. Do not push the same version again. If RubyGems confirms that the version is absent and the tag points to the verified commit, correct the authentication or transport problem and push the retained, digest-verified artifact with `asdf exec gem push --host https://rubygems.org /absolute/path/to/rails-mmd-0.1.0.gem`. Keep the existing tag. A source change requires a new version and the normal verification process; do not move a published tag or replace a published version.
