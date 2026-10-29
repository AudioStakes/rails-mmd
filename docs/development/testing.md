# Testing generation behavior

Run the commands in [tooling.md](tooling.md) and use the local
[pre-commit/pre-push hooks](hooks.md) for final verification. The default Rake
gate runs the full RSpec suite and the real Rails matrix once each. RSpec's
matrix-task specs exercise orchestration and failure handling with system-boundary
fakes; the real matrix runs separately through `verify:rails_matrix`.

## Executable contracts

| Location | What it verifies |
|---|---|
| `schemas/` and `fixtures/schemas/` | Closed config, diagnostics, IR, and render-plan shapes; accepted examples and deliberately invalid payloads |
| `fixtures/mermaid/` and `spec/rails_mmd/mermaid_serializer_spec.rb` | ER/class syntax emitted by the serializer, labels, markers, attributes, directions, and comments |
| `spec/contracts/schema_spec.rb` | All valid fixtures pass and all invalid fixtures fail; diagnostic codes and metadata remain aligned |
| `spec/contracts/drift_guard_spec.rb` | Current contract/usage and repository policy remain consistent with the executable interface |
| `spec/rails_mmd/` | Pipeline stages, association normalization, deterministic output, redaction, and failure paths |
| `spec/gem/` | Runtime range, package contents, and execution of the built gem outside the checkout |
| `spec/integration/rails_matrix_task_spec.rb` | Matrix selection, prerequisites, command failures, and exact artifact-oracle enforcement |
| `fixtures/rails_matrix/template/` | Real Rails model declarations, schema, config, and expected relationships/diagnostics/polymorphic groups |

Keep fixture output paths relative to the project root. Contract checks do not
require Node, Mermaid CLI, or a hosted service. Mermaid checks validate the
supported serializer contract; they are not a browser rendering test or a proof
that every Mermaid renderer version behaves identically.

## Association changes

Verify reflection behavior in the shared real Rails app and extend its exact
expectations on every pair in
[`fixtures/rails_matrix/matrix.yml`](../../fixtures/rails_matrix/matrix.yml).
The matrix compares relationship IDs, endpoints, labels, cardinalities, complete
structured diagnostic projections, and polymorphic group membership/FK
attributes. It also validates JSON schemas and requires Mermaid output to match
the validated render plans. Exit success or nonempty files alone are insufficient.

Keep unit doubles for failures or declaration combinations that real model
classes cannot express. Test through a stage's consumed interface or the CLI,
not private helper names. When normalizing aliases or reciprocal declarations,
check that reversing declaration order leaves the output unchanged.

## Blocking and warning failures

The [diagnostic catalog](../contract.md#diagnostics) is the policy reference for
exit categories, attachment, and publication effects. Relevant examples should
assert the observable outcome together:

- Config/output-setup errors: exit `2`, sanitized stderr JSON, empty stdout, and
  no files written.
- Rails/domain/required-schema errors: exit `2`; diagnostics publish when a safe
  output directory is available, and affected domains' Mermaid/render plans are
  omitted while unaffected selected domains can publish.
- Serialization or exhausted safe-token collisions: exit `3` and no artifacts
  for the blocked domain; resolved collisions remain warnings.
- Write/replacement failures: exit `4`; rollback preserves prior managed files
  where possible. Failed rollback retains unrestored backup files and supplies
  recovery guidance.
- Unexpected implementation errors: exit `99` with sanitized diagnostics and no
  raw backtrace.
- Warning-only runs: exit `0`, or `1` with `--fail-on-warning`, with identical
  publication rules and silent stdout/stderr on successful publication.

Publication specs also cover stale managed-file removal, unselected-domain and
unrelated-file preservation, symlink rejection, duplicate identities, and
cross-domain diagnostic-reference rejection. Sanitization checks must preserve
valid schema names containing credential-like words while rejecting credential
values, unsafe paths, and control characters in free text.

## Compatibility evidence

The real matrix uses a fresh copied SQLite application and frozen per-series
locks for each declared Ruby/Rails pair. See [ci.md](ci.md) for runtime setup,
single-pair diagnosis, and the trusted cache boundary. A passing matrix proves
those declared pairs and fixtures; it does not establish support for untested
database adapters, other runtime combinations, or arbitrary application
initializers.
