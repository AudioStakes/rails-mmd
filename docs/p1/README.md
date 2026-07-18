# P1 Engineering Records

Each P1 feature keeps its delivery evidence under `docs/p1/<feature>/`:

- `research.md`: verified repository and upstream facts, alternatives, and risks.
- `design.md`: accepted behavior, public test seams, file-level plan, and review record.
- `implementation.md`: TDD red/green evidence, verification commands, and residual risks.

Advance phases only in this order:

1. Research, then specialist review/correction until no findings remain.
2. Design, then specialist review/correction until no findings remain; confirm
   the public TDD seams before adding tests.
3. Implement one red/green slice at a time, then specialist review/correction
   until no findings remain.

Do not use these records as a second specification. Product behavior remains in
the applicable contract or support matrix. Promote only stable, repository-wide
operating knowledge to `AGENTS.md`, and link to the detailed record instead of
duplicating it.
