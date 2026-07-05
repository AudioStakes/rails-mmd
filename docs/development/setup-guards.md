# Setup Guards

This repository is still in pre-runtime setup mode. The contract specs include
drift guards that fail loudly when future changes move the project away from the
agreed Ruby-only, repair-first, P0-scoped setup.

## Repair-First Loop

Use the hooks as the final evidence path:

1. Run the repair step first.
2. Inspect the deterministic diff.
3. Stage only the intended repairs.
4. Let read-only checks run after the staged tree is explicit.

Codex should use `pre-commit` and `pre-push` hooks for final evidence. Direct
Rake tasks are for diagnosis, narrowing failures, or reproducing hook output
before the hook is run again.

## rails-mmd generate guard release condition

`rails-mmd generate` is intentionally unroutable before the P0 implementation
slices land. A later config, diagnostic, or artifact implementation issue may
update or remove the generate guard only in the same PR that adds the matching
contract specs and the corresponding P0 implementation slice.

The guard must fail if `rails-mmd generate` appears in help, routes to a stub,
returns success, writes artifacts, or exposes pre-P0 behavior before that
release condition is met.

## Future P0 Sequence

The future implementation sequence from `docs/p0-contract.md` is:

1. Config loader and schema validation.
2. Rails boot and eager load.
3. Model inventory.
4. Domain resolution.
5. Selected schema probe and connection guard.
6. Relationship builder.
7. IR normalization and safe tokens.
8. Render-plan generation.
9. Mermaid serialization.
10. Diagnostics and exit policy.
11. Redaction.
12. Atomic artifact publishing.
13. CLI integration.

This setup guard documentation does not authorize implementing those tasks in
the setup PR.
