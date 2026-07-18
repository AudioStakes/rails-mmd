# P1-01 Runtime Compatibility Research

Status: research complete; reviewed with no remaining findings

## Target

Validate rails-mmd against the latest patch releases in the supported Rails 7.2
and 8.1 series. Cover the Ruby 3.3/4.0 boundaries with three high-signal pairs
instead of a Cartesian matrix.

## Repository facts

- `rails-mmd.gemspec` now requires Ruby `>= 3.3, < 4.1` and has no direct
  `activesupport` dependency.
- `RailsMmd::RailsLoader#boot` loads the target application's
  `config/environment.rb` and eager-loads its `Rails.application`.
- `RailsMmd::Generate#run` reads `ActiveRecord::Base` from the target Rails
  application. Active Record itself is not a rails-mmd runtime dependency.
- No file under `lib/` or `exe/` references Active Support directly. The direct
  `activesupport` dependency is therefore coupling, not an implementation need.
- The local `pre-push` hook runs the default Rake verification task. Hosted
  GitHub Actions are intentionally disabled.
- The documented gate pins Ruby 4.0.6 through asdf, while `lefthook.yml` invokes
  bare `bundle exec rake`; this toolchain mismatch must be resolved in design.
- Existing fixtures cover contracts and serializers; no real Rails application
  fixture boots the CLI across Rails versions.

## Upstream facts

The table uses the latest non-prerelease versions reported by the RubyGems Rails
package API on 2026-07-18. `Required Ruby` is package metadata, not a guarantee
that every later Ruby release is compatible.

| Rails series | Test release | Required Ruby | Rails maintenance status |
|---|---:|---:|---|
| 7.2 | 7.2.3.1 | `>= 3.1.0` | security-only through 2026-08-09 |
| 8.1 | 8.1.3 | `>= 3.2.0` | bug fixes through 2026-10-10; security fixes through 2027-10-10 |

The common Ruby floor allowed by both Rails packages is 3.2. The rails-mmd
support floor still requires an explicit design decision and executable matrix
evidence; package minima alone are insufficient.

## Dependency strategy

| Option | Lifecycle cost | Determinism | Result |
|---|---|---|---|
| Appraisal | Adds a development dependency and generated bundle surface | Good | Reject unless plain Bundler files prove inadequate |
| Repository-owned version Gemfiles and lockfiles | More files, but explicit resolution per Rails series | Best | Preferred |
| Ad hoc generated Gemfiles | Small initial diff; resolution can drift between runs | Weak | Reject for the verification gate |

Removing the unused direct `activesupport` dependency is smaller and less
coupled than broadening it. If later implementation requires Active Support, the
fallback is a bounded `>= 7.2, < 8.2` constraint proven by the matrix.

The root lock currently records Ruby 4.0.6 and Active Support 8.1.3. It cannot
serve as the deterministic resolution for all Rails series; matrix bundles need
separate locks and isolated Bundler configuration.

## Harness constraints

These are required implementation outcomes. None is wired into the current
default Rake or pre-push gate yet.

- Exercise the user-visible CLI from a real, minimal Rails application bundle.
- Observe exit status, stdout/stderr diagnostics, and published artifacts.
- Keep one deterministic dependency resolution per Rails series.
- Reuse one repository-owned minimal application template where Rails-generated
  version noise is irrelevant.
- Run the compatibility matrix from the local pre-push gate.
- Keep Bundler caches outside tracked fixtures; a warm cache may improve speed
  but must not affect correctness.

## Risks and required design decisions

- A Rails package's lower Ruby bound does not prove compatibility with Ruby 4.0
  or with rails-mmd's selected Ruby range.
- Rails 7.2 is security-only. Compatibility testing does not extend Rails'
  maintenance promise.
- Running three bundle checks on every pre-push can be slow. Locks and a
  shared cache must preserve deterministic results without hiding missing gems.
- The fixture must execute rails-mmd from the checkout while resolving Rails and
  Active Support from the fixture bundle.
- The public TDD seam must be confirmed before any implementation test is added.

## Research review record

| Round | Perspective | Findings | Research correction |
|---|---|---|---|
| 1 | dependency management | Current dependency and lock cannot admit all targets; Ruby lock coupling was implicit | Recorded direct-dependency removal and isolated per-series locks as design inputs |
| 1 | build harness | Desired matrix was easy to mistake for current gate behavior; toolchain pin mismatch was absent | Marked all harness items as pending outcomes and recorded the mismatch |
| 1 | Rails compatibility | Security-only phases and Rails' series-level Ruby guidance were not explicit | Clarified maintenance phases and added the Rails upgrade guide |
| 2 | build harness | None | No change |
| 2 | Rails compatibility | None | No change |
| 2 | dependency management | Review scope initially required implementation during research | Clarified that proposed dependency and lock changes are design inputs |
| 3 | dependency management | None | No change |

## Sources

- [RubyGems Rails package API](https://rubygems.org/api/v1/versions/rails.json)
- [Rails 7.2.3.1 package metadata](https://rubygems.org/gems/rails/versions/7.2.3.1)
- [Rails 8.1.3 package metadata](https://rubygems.org/gems/rails/versions/8.1.3)
- [Rails maintenance policy](https://rubyonrails.org/maintenance)
- [Rails upgrade guide: Ruby versions](https://guides.rubyonrails.org/upgrading_ruby_on_rails.html#ruby-versions)
- [Rails 7.2.3.1, 8.0.4.1, and 8.1.2.1 security release](https://rubyonrails.org/2026/3/23/Rails-Versions-7-2-3-1-8-0-4-1-and-8-1-2-1-have-been-released)
- [Rails 8.0.5 and 8.1.3 release](https://rubyonrails.org/2026/3/24/Rails-Versions-8-0-5-and-8-1-3-have-been-released)
