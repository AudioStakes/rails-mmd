# Setup Guards

This repository keeps contract specs that fail loudly when changes move the
project away from the agreed Ruby-only, repair-first, P0-scoped setup.

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

`rails-mmd generate` is routed only after the internal P0 implementation slices
land. The guard now expects the command to exist and to return current-contract
pre-output diagnostics for a missing config.

The guard must fail if `rails-mmd generate` routes to a stub, returns success
without valid input, writes artifacts for pre-output fatal diagnostics, or
exposes non-P0 behavior.

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

The CLI integration slice owns releasing the generate guard.
