# P1-01 Runtime Compatibility Design

Status: design complete; reviewed with no remaining findings

## Decisions

### Supported runtime range

- rails-mmd will require Ruby `>= 3.3, < 4.1`. Ruby 3.3 is the oldest Ruby
  series still maintained on 2026-07-18; Ruby 3.2 is EOL.
- The unused direct `activesupport` dependency will be removed. Active Support
  and Active Record come from the target Rails application bundle.
- Compatibility means the latest patch in Rails 7.2 and 8.1 boots a real app and
  completes `rails-mmd generate` for the declared pairs. It does not extend
  Rails' maintenance promise.

### Executable matrix

The repository-owned manifest declares three pairs selected for maximum boundary
coverage. Each series bundle pins its exact Rails patch, avoiding duplicate
version declarations.

| Rails | Ruby | Signal |
|---:|---:|---|
| 7.2.3.1 | 4.0.6 | oldest Rails with newest Ruby |
| 8.1.3 | 3.3.12 | newest Rails with oldest Ruby |
| 8.1.3 | 4.0.6 | current baseline |

This is an executable rails-mmd support boundary, not an upstream guarantee that
all future Ruby patches work. Intermediate Ruby 3.4 is inside the tested bounds
but is not a separate matrix axis.

### Fixture and bundle isolation

- `fixtures/rails_matrix/template/` contains one hand-written,
  lowest-common-denominator Rails application with SQLite, `Author` and `Post`,
  and the checked-in rails-mmd config. It is not generated from any Rails series
  and avoids version-specific generated settings such as `cache_classes`,
  `enable_reloading`, and `autoload_lib`.
- `fixtures/rails_matrix/bundles/<rails-series>/` contains the pinned Gemfile and
  lockfile for one Rails series. Locks are generated under Ruby 3.3.12 with all
  supported platforms recorded. Gemfiles are hand-authored without a `ruby`
  directive, so their frozen locks contain no single-Ruby pin.
- For each pair, the runner creates a fresh temporary child directly under
  `.bundle/rails-matrix/apps/`, copies the template and selected bundle, and
  removes the child afterward. Both the tracked bundle directory
  (`fixtures/rails_matrix/bundles/<series>`) and runtime child
  (`.bundle/rails-matrix/apps/<pair>`) are four levels below the checkout, so the
  Gemfile's `../../../..` rails-mmd path is stable.
- Matrix Bundler runs use frozen mode. The Ruby 4.0.6 pass must consume the
  floor-generated lock without modifying it; incompatibility is a matrix failure,
  not an opportunity to re-resolve.
- Bundler installs into `.bundle/rails-matrix/gems/<ruby-version>/`; this cache is
  ignored by Git. Frozen lock validation and `bundle check` make the shared cache
  correctness-neutral.
- SQLite constraints match the corresponding Rails generator metadata: Rails
  7.2 uses `>= 1.4`, and Rails 8.1 uses `>= 2.1`. Checked-in locks select exact
  versions.

### Local verification gate

- `bundle exec rake verify:rails_matrix` is the developer-facing matrix command.
- The task fails with a concise setup instruction if asdf lacks Ruby 3.3.12 or
  4.0.6, or if the required Bundler version is unavailable for either Ruby.
- Each subprocess fixes its working directory and `BUNDLE_GEMFILE`. Each pair
  runs bundle check/install, database preparation, and
  `bundle exec rails-mmd generate`; it never invokes the root default Rake task.
- Success requires exit status 0 and the expected diagnostics, render-plan, and
  Mermaid artifacts. JSON is checked through the existing contract schemas and
  Mermaid through shared serializer-contract helpers, not matrix-specific golden
  copies.
- The default Rake task includes `verify:rails_matrix`, so the existing pre-push
  hook remains the single CI-equivalent entry point.
- `RAILS_MMD_MATRIX_PAIR=<ruby>-<rails>` selects one declared pair for diagnosis;
  the default and pre-push paths always run all pairs.
- `docs/development/ci.md` and `.ruby-version` use Ruby 4.0.6, removing the
  existing documented-command/Lefthook mismatch by making the default project
  Ruby authoritative. Matrix subprocesses select their explicit Ruby version.

## Public TDD seams

Implementation tests will observe only these seams:

1. Package seam: building or resolving the rails-mmd gem exposes Ruby
   `>= 3.3, < 4.1` and no direct Active Support dependency.
2. Developer command seam: `bundle exec rake verify:rails_matrix` returns success
   only when every required pair executes and passes, identifies a failing pair,
   and emits a concise setup instruction when Ruby or Bundler is missing.
3. Product command seam: inside each copied real Rails app,
   `bundle exec rails-mmd generate` returns exit status 0 and publishes the
   schema-valid diagnostics/render plans and contract-valid Mermaid artifacts.

Process execution, filesystem copies, and asdf/Bundler calls are system
boundaries and may be replaced with fake executables/filesystems while exercising
the public Rake command. RailsMmd product and tooling classes are not mocked or
tested directly.

`RailsMatrix::Runner#run` is an internal orchestration boundary that keeps the
Rake adapter thin; it is not a public test seam.

## TDD slices

1. Red: package compatibility assertion fails on the current Ruby and Active
   Support constraints. Green: change gem metadata and refresh the root lock.
2. Red: the public matrix Rake command is absent. Green: add the smallest runner
   that validates the manifest and reports pair failures using boundary fakes.
3. Red: missing Ruby or Bundler leaks raw tool errors. Green: emit the documented
   setup instruction and non-zero status through the developer command.
4. Red: a real Rails 8.1 app cannot complete the product command through the new
   fixture harness. Green: add the shared app template and Rails 8.1 bundle.
5. Repeat one failing real-app example for Rails 7.2; make only the smallest
   compatibility change needed.
6. Red: the default verification contract omits the matrix. Green: connect the
   verified task and update setup/CI documentation.
7. Refactor only after all acceptance examples are green.

## Planned file changes

| Path | Purpose |
|---|---|
| `rails-mmd.gemspec`, `.ruby-version`, `Gemfile.lock` | Runtime range and root development bundle |
| `.gitignore` | Ignore matrix app and gem caches |
| `Rakefile`, `tooling/rails_matrix.rb` | Thin public task and orchestration kept outside shipped `lib/` |
| `fixtures/rails_matrix/matrix.yml` | Exact supported pairs |
| `fixtures/rails_matrix/template/**` | Shared minimal Rails app |
| `fixtures/rails_matrix/bundles/**` | Per-series Gemfiles and locks |
| `spec/integration/rails_matrix_task_spec.rb` | Public Rake command behavior through system-boundary fakes |
| `docs/development/ci.md`, `docs/development/dependencies.md` | Setup, gate, support caveats, update procedure |
| `docs/p1/01-runtime-compatibility/implementation.md` | Red/green and verification evidence |
| `AGENTS.md` | Stable P1 record and matrix-update routing only |

## Acceptance criteria

- All three declared Rails/Ruby pairs pass from clean copied fixture apps.
- The manifest is the versioned matrix source of truth and contains Rails 7.2
  and 8.1, both Ruby boundaries, and the current baseline. The command fails
  when a declared pair is unexecuted or failing and names the pair.
- Every successful pair publishes schema-valid diagnostics/render plans and
  contract-valid Mermaid output; exit status or file existence alone is not
  sufficient.
- Missing Ruby/Bundler prerequisites produce a concise setup instruction and
  non-zero status.
- The root gem installs without forcing an Active Support version.
- The default Rake task and pre-push hook exercise the matrix.
- Documentation names Rails 7.2 and 8.1 as the supported series.
- No hosted workflow or Appraisal dependency is added.

## Design review record

| Round | Perspective | Findings | Design correction |
|---|---|---|---|
| 1 | architecture | Artifact assertions risked a second oracle; runner boundary and shipped/tooling split were implicit | Reused contract validators, named the runner seam, and kept orchestration outside `lib/` |
| 1 | build engineering | Relative-path claim, cross-Ruby lock behavior, clean isolation, cache checks, and diagnosis cost needed precision | Documented equal-depth bundle paths, frozen floor locks, per-pair temp apps, cache checks, and pair selection |
| 1 | QA | Pair state could leak; prerequisite errors and exact output assertions lacked TDD coverage; manifest-removal wording was implementation-coupled | Added clean pair isolation, prerequisite slice, exact contract assertions, and required-pair execution semantics |
| 1 | Rails runtime | Generated Ruby pins/config could break cross-version reuse; SQLite bounds were imprecise | Required hand-authored Ruby-neutral bundles/config and recorded per-series SQLite bounds |
| 2 | architecture | None | No change |
| 2 | build engineering | None | No change |
| 2 | Rails runtime | None | No change |
| 2 | QA | Internal runner was incorrectly listed as a public TDD seam | Kept tests on the Rake/product commands and marked the runner as an untested internal boundary |
| 3 | architecture | None | No change |
| 3 | QA | None | No change |
| 4 | architecture | AGENTS risked duplicating phase policy | Kept AGENTS as routing and moved the policy to `docs/p1/README.md` |
| 5 | architecture | None | No change |
| Scope revision | product | Ten pairs were excessive; Rails 7.2 and 8.1 are sufficient | Reduced to three pairs that maximize cross-boundary and current-version signal |
