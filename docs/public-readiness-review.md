# Public readiness review

Review date: 2026-09-29. Baseline: `9143a7a` on `main`.

This review covers the repository that will become public, including its Git
history and GitHub discussions, and the first-time user and contributor paths.
Unmerged work in other checkouts is outside this assessment. The repository
visibility was not changed by this review.

## Decision

Suitable for public access after these repairs are merged, within the documented
support limits. The final independent review found no additional blocking
defect, and the local verification gates passed. Confirm a monitored private
security-reporting channel as described below. This is an assessment of the
reviewed repository state, not a production-safety guarantee for arbitrary Rails
applications or a promise of a published RubyGems release.

## Review and repair rounds

Five parallel specialist reviews covered onboarding, security, packaging,
contribution, and runtime behavior. A separate reviewer then challenged the
combined changes and reported further CLI input-validation issues.

| Area | Finding | Resolution |
| --- | --- | --- |
| First diagram | Prerequisites, execution directory, silent success, and Mermaid viewing were unclear | README and usage guide now explain the complete path |
| Configuration | Allowed settings and common failures were hard to discover | Added configuration reference and troubleshooting |
| Output location | README suggested keeping output outside the repository although paths must remain inside the app root | Documented an ignored directory within the application |
| Gem contents | User guide linked to an absent support matrix | Included the matrix and regression coverage; repository-only links use GitHub URLs |
| Contributor setup | Implicit Ruby selection depended on local asdf settings | Explicit pinned Ruby/Bundler setup, fork-to-PR instructions, and reporting templates |
| CLI input | Misspelled switches and positional arguments could be ignored | Reject invalid arguments before generation and improve command help |
| CLI input, second review | String options without values could silently use the option name as a value | Reject missing values before generation; preserve valid explicit values |
| Output paths | A valid root-contained name such as `..diagrams` was rejected | Compare path components while retaining root-escape and symlink guards |
| Fixture dependencies | Rails, JSON, and SQLite fixture locks included vulnerable versions | Update affected dependencies and audit every maintained lockfile |
| Security reporting | No repository security policy | Added trusted-app boundaries, artifact handling, and reporting guidance |

The dependency findings concern development fixture applications, not a Rails
dependency imposed by the published gem. Advisories were checked against both
OSV and Bundler Audit. OSV initially missed the SQLite advisory, so the review
also used Bundler Audit:

- [Active Storage advisory GHSA-xr9x-r78c-5hrm](https://github.com/rails/rails/security/advisories/GHSA-xr9x-r78c-5hrm)
- [JSON advisory GHSA-9hj4-r449-hfvc](https://github.com/ruby/json/security/advisories/GHSA-9hj4-r449-hfvc)
- [SQLite advisory GHSA-mwm8-39rw-8826](https://github.com/sparklemotion/sqlite3-ruby/security/advisories/GHSA-mwm8-39rw-8826)

## Public-data review

The security review inspected 204 commits, 1,181 distinct Git blobs, and 59
locally available refs for known credential signatures and unsafe tracked file
names. It also inspected 82 GitHub issue/PR bodies and 14 issue comments;
57 PRs had no inline comments or review summaries. No matching secrets or
unexpected private paths were found. There were no releases, release assets,
or GitHub Actions artifacts at inspection time. MIT licensing and gem metadata
agree.

This is a bounded review, not a guarantee that no sensitive material exists.
Unknown secret formats, personal information in ordinary prose, external
links and image contents, deleted content, and GitHub objects outside the
available refs were not exhaustively examined. Author and committer email
addresses in Git history become public with the repository.

## Verification evidence

The following checks passed on the repaired working tree:

- `ASDF_RUBY_VERSION=4.0.6 asdf exec bundle exec lefthook run pre-commit`:
  repair-first lint, affected specs, dependency checks, and contract checks.
  An initial contract check rejected the edited exit-code table; the original
  table was preserved and CLI usage errors were documented separately before
  rerunning the hook successfully.
- `ASDF_RUBY_VERSION=4.0.6 asdf exec bundle exec lefthook run pre-push --force`:
  the complete default Rake gate, including lint, all specs, coverage, dependency
  auditing, and all three declared real-app matrix pairs (Ruby 4.0.6/Rails 7.2,
  Ruby 3.3.12/Rails 8.1, and Ruby 4.0.6/Rails 8.1). `--force` ensures the manual
  check runs even before the branch has commits to push.
- After refreshing advisory data, Bundler Audit found no vulnerabilities in
  the root or either fixture lockfile. OSV also returned no findings for the
  final root/7.2/8.1 sets of 71/71/72 distinct packages. Rails fixtures now pin
  7.2.3.2 and 8.1.3.1; affected JSON and SQLite dependencies use 2.21.2 and 2.9.6.
- `gem build rails-mmd.gemspec` succeeded. The gem contained the expected 40
  files, including the license and user-facing guides, with no unexpected
  packaged files.
- A separate disposable Rails application successfully installed the existing
  GitHub source using the README instructions, loaded its schema, and generated
  ER/class diagrams and diagnostics. The repaired built-gem contents also ran
  successfully in a separate application without repository development files.
- Regression tests demonstrated failures before fixes and passed afterward
  for gem guide inclusion, CLI input rejection, root-contained output paths,
  and fixture dependency audit coverage/failure propagation.
- README/usage YAML examples validated against the actual configuration schema;
  documented defaults matched the implementation; local documentation links
  and packaged-guide links resolved. A third review independently exercised
  missing option values, valid explicit values, help, and boolean handling.

## Publication and support limits

- The repository is currently private. Merge the reviewed repairs before
  changing visibility. A public repository does not by itself publish a gem
  release to RubyGems; the supported installation path remains GitHub/Bundler.
- GitHub's private vulnerability reporting API returned 404 during this
  review, so a working private reporting channel could not be confirmed.
  Verify a monitored private channel when opening the repository; do not ask
  reporters to disclose exploit details in a public issue. See
  [SECURITY.md](../SECURITY.md).
- The README and association matrix describe the tested Ruby/Rails pairs,
  SQLite-based integration evidence, and unsupported features. These results
  do not establish PostgreSQL/MySQL adapter coverage or untested combinations.
- The CLI boots and eager-loads the target application's Ruby code. Use only
  trusted applications/configuration and review generated diagrams and
  diagnostics before sharing. Application initializers retain their normal
  side effects.
- Hosted GitHub Actions are intentionally disabled by repository policy.
  Local hooks provide verification evidence; this PR does not change that
  operating model.
