# P1-02 Association Detection Design

Status: design complete; reviewed with no remaining findings

## Decisions

### Inventory and classification

- Enumerate `reflect_on_all_associations` without a macro. Fall back to
  `reflections.values` only when the primary API is unavailable.
- Continue sending `belongs_to` reflections through the existing eligibility,
  key, domain, cardinality, and rendering path.
- For every other reflection, emit exactly one warning and no relationship.
  Do not call `klass`, target/key resolution, scope bodies, or through/source
  resolution.
- Read only `name` and `macro` for P1-02. Later PRs own deeper classification
  and rendering.

### Diagnostic contract

- Add one public code: `ASSOCIATION_MACRO_OMITTED`.
- Add a dedicated closed metadata shape requiring `domain_id`,
  `owner_constant`, `association_name`, and `association_macro`.
- Store `association_macro` as a structured snake-case string. Do not create one
  public code per macro; later PRs can support subsets without renaming the
  remaining warning.
- Preserve warning severity, exit code 0 by default, `relationship_build` phase,
  and relationship scope. `--fail-on-warning` retains its existing exit policy.
- Keep builder iteration order internal. Published diagnostics use the existing
  `Ordering.sort_diagnostics` contract; tests compare the stable published order or
  key projections, not Rails reflection order.

### Real-Rails acceptance

- Add a versioned expected-diagnostics JSON file to the shared Rails matrix app.
  For each code declared by the expectation, compare code, severity, phase,
  scope, subject ID, and the complete metadata object; exclude only generated ID
  and prose fields so unrelated P0 diagnostics remain independently owned.
- Extend the matrix artifact validator to compare the generated diagnostics with
  that expectation. The app declares `Author.has_one :profile`,
  `Author.has_many :posts`, and `Author.has_and_belongs_to_many :tags`; the
  missing target constants also prove inventory does not resolve targets. The
  three warnings (`posts`, `profile`, `tags`) must match the existing published diagnostic order and the app
  must still publish ER/Class artifacts.
- This expectation is intentionally updated by later P1 PRs when a formerly
  omitted association becomes renderable.

### Contract ownership

- Update the executable diagnostic schema, valid catalog fixture, and P0
  diagnostic catalog together.
- Clarify the P0 sentence about silent non-`belongs_to` omission as a baseline;
  the Rails 7.2/8.1 support matrix owns the P1 extension.
- Mark P1-02 as supported only after the matrix and full local gate pass. P1-03
  remains the next incomplete row.

## Public TDD seams

1. Library seam: `RelationshipBuilder#build` returns existing `belongs_to`
   relationships plus one schema-valid warning for each non-`belongs_to`
   reflection, without resolving its target.
2. Product seam: `bundle exec rails-mmd generate` in each matrix app publishes
   the exact expected warning and valid artifacts with exit 0.
3. Contract seam: schema/catalog drift specs accept the new code and reject
   missing or unknown macro metadata.

Reflection helper methods and diagnostic construction helpers remain private and
are not test seams.

## TDD slices

1. Red: the real matrix expectation finds no diagnostic for `Author.posts`.
   Green: inventory all reflections and emit the smallest schema-backed generic
   warning while preserving current `belongs_to` output.
2. Red: fixtures missing `association_macro`, adding an extra field, or using a
   non-snake-case macro pass. Green: close the schema and route all three
   fixtures through `schema_spec`.
3. Red: a non-`belongs_to` reflection whose target resolution raises breaks the
   build. Green: prove P1-02 reads only `name` and `macro`.
4. Refactor only after all three public seams are green.

## Planned changes

| Path | Purpose |
|---|---|
| `lib/rails_mmd/relationship_builder.rb` | Enumerate and classify all reflections |
| `schemas/diagnostics.schema.json` | Add code and closed macro metadata shape |
| `fixtures/schemas/diagnostics/valid/catalog.json` | Add canonical warning fixture |
| `fixtures/schemas/diagnostics/invalid/association_macro_*.json` | Missing, extra, and malformed metadata cases |
| `fixtures/rails_matrix/template/rails_mmd_expected_diagnostics.json` | Real-app expectation |
| `fixtures/rails_matrix/template/app/models/author.rb` | Declare all three omitted macro kinds |
| `tooling/rails_matrix.rb` | Validate expected diagnostic projections |
| `spec/rails_mmd/relationship_builder_spec.rb` | Public library behavior and no target resolution |
| `spec/contracts/schema_spec.rb` | Closed schema behavior |
| `docs/p0-contract.md` | Baseline/P1 diagnostic contract alignment |
| `docs/active-record-association-support.md` | Completion status and next feature |
| `docs/p1/02-association-detection/implementation.md` | Red/green and verification evidence |

## Acceptance criteria

- Rails 7.2.3.1 and 8.1.3 enumerate `belongs_to`, `has_one`, `has_many`, and
  HABTM through the same primary API.
- Every non-`belongs_to` reflection yields one `ASSOCIATION_MACRO_OMITTED`
  warning with its macro; no target resolution occurs.
- Existing eligible and omitted `belongs_to` behavior is unchanged.
- The three real Rails/Ruby pairs publish exactly ordered warnings for
  `Author.profile`, `Author.posts`, and `Author.tags`, plus valid render plans
  and matching Mermaid with exit 0.
- Published diagnostics are deterministic and schema-valid.
- Default Rake, pre-commit, and pre-push gates pass.

## Design review record

| Round | Perspective | Findings | Correction |
|---|---|---|---|
| 1 | Rails runtime | None | No change |
| 1 | QA | Negative schema cases were not executable; the real-app oracle omitted required metadata; one warning could not prove ordering or all macros | Added three invalid fixtures, complete metadata comparison, and three real macro warnings in published order |
| 2 | Rails runtime | None | No change |
| 2 | QA | None | No change |
