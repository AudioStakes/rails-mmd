# P2 Engineering Records

Each P2 feature keeps its delivery evidence under `docs/p2/<feature>/`:

- `research.md`: verified repository and upstream facts, alternatives, risks,
  and research review corrections.
- `design.md`: accepted behavior, public TDD seams, vertical slices, file-level
  plan, and design review corrections.
- `implementation.md`: red/green evidence, verification commands, implementation
  review corrections, and residual risks.

Advance phases only in this order:

1. Research, then specialist review and correction until no findings remain.
2. Design, then specialist review and correction until no findings remain.
3. Implement one public-seam red/green slice at a time, then run specialist
   review and correction until no findings remain.

The support matrix remains the product scope. These records preserve evidence
and decisions; they do not silently expand a P2 item into adjacent items.

