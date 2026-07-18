# P2-02 Single-Table Inheritance Design

Status: complete

## Goal

Represent loaded, selected Active Record STI families without changing the
physical-table meaning of ER entities or association endpoints.

- ER artifacts contain one physical base entity per shared table.
- Class artifacts additionally contain synthetic concrete subtype entities and
  explicit inheritance edges.
- Explicit selection of an STI subtype remains non-renderable and keeps the
  existing `DOMAIN_MODEL_NOT_RENDERABLE` diagnostic.
- No stage reads discriminator rows or discovers unloaded constants.

This design implements the boundary chosen in `research.md`. It does not change
`docs/p0-contract.md`.

## Stage ownership and handoff

`ModelInventory` remains schema-free. It continues to classify a directly
selected subtype as non-renderable, but its complete loaded-record inventory is
also passed to `SchemaProbe`, the first schema-observing stage.

```text
ModelInventory::Result.records
  ├─> DomainResolver (selected physical base records)
  └─> SchemaProbe#probe(domains:, inventory_records:)
          ├─> DomainResult.entities       (physical entities only)
          └─> DomainResult.sti_subtypes   (logical subtype metadata)

DomainResult.entities ─> RelationshipBuilder (physical associations only)
DomainResult.entities + sti_subtypes + relationships ─> IrBuilder
```

`Generate#internal_payloads` is the only orchestration call-site change:

```ruby
schema_probe.probe(
  domains: resolved.domains,
  inventory_records: inventory.records
)
```

`inventory_records:` defaults to an empty array for direct unit consumers. The
default means "no loaded descendant evidence", not "discover descendants".

## Schema-probe model

`SchemaProbe::DomainResult` gains `:sti_subtypes`. A subtype is deliberately not
a `SchemaProbe::Entity`, because it does not own a second physical table.

```ruby
StiSubtype = Struct.new(
  :entity_id,
  :base_entity_id,
  :parent_entity_id,
  :ruby_constant,
  :table_name,
  :inheritance_column,
  :sti_name,
  :depth,
  keyword_init: true
)
```

Subtype discovery runs only after the selected base entity has been probed
successfully. For each inventory candidate, all of the following must hold:

1. the candidate constant differs from the selected base constant;
2. the candidate and base have the same connection-context identity;
3. the candidate constant resolves to a named class;
4. `candidate.base_class.equal?(base_model)`;
5. candidate and base have the same exact effective `table_name`;
6. candidate and base have the same exact effective `inheritance_column`;
7. `candidate.descends_from_active_record?` is false; and
8. `candidate.abstract_class?` is false.

The predicate intentionally does not use `base_class != model` by itself. It
also never queries discriminator values, calls `descendants`, or constantizes a
name absent from the inventory.

Runtime metadata calls are isolated behind narrow safe helpers for
`base_class`, `abstract_class?`, `descends_from_active_record?`,
`inheritance_column`, `sti_name`, `table_name`, `superclass`, and `name`.
Selected-base probe failures keep the existing blocking behavior. A candidate
whose STI metadata cannot be read is omitted without damaging the physical
entity. P2-02 does not add a new public diagnostic for an unselected candidate;
the omission is deterministic and avoids expanding the diagnostic contract for
best-effort logical metadata.

### Identity and parent resolution

The physical base keeps its existing ID:

```text
entities/<table_name>
```

A subtype ID is independent of `sti_name` and preserves the fully qualified
Ruby constant verbatim:

```text
<base_entity_id>/sti/<fully-qualified-ruby-constant>
entities/vehicles/sti/Admin::Car
```

This distinguishes constants with equal demodulized `sti_name` values. Mermaid
never consumes this ID directly; the safe-token allocator still supplies the
grammar-safe renderer identifier.

For each accepted subtype, walk `superclass` toward the selected base. The first
accepted concrete subtype encountered is the visible parent. Abstract
intermediates are skipped. If no accepted subtype is encountered before the
base, the physical base is the parent. A walk that escapes the family omits the
candidate.

Candidates are considered in `ruby_constant` order. Final subtype records sort
by `[depth, entity_id]`.

## IR v3 contract

IR and render-plan payloads move from schema version 2 to 3. Config and
diagnostics remain version 1. There is no dual-write or compatibility flag.

The IR top-level shape keeps all v2 fields. Its entity object gains one optional
`metadata` member, expressed as a closed discriminator union. Keeping the
immediate parent only in subtype metadata makes it the normalized source of
truth; the IR does not duplicate it in a second edge collection.

### Physical entity

```json
{
  "entity_id": "entities/vehicles",
  "ruby_constant": "Vehicle",
  "table_name": "vehicles",
  "attributes": [],
  "metadata": {
    "kind": "sti_base",
    "inheritance_column": "type"
  }
}
```

A non-STI physical entity omits `metadata`. A physical base with at least one
visible subtype requires the exact two-member `sti_base` metadata above.

### STI subtype entity

```json
{
  "entity_id": "entities/vehicles/sti/Admin::Car",
  "ruby_constant": "Admin::Car",
  "table_name": "vehicles",
  "attributes": [],
  "metadata": {
    "kind": "sti_subtype",
    "base_entity_id": "entities/vehicles",
    "parent_entity_id": "entities/vehicles",
    "inheritance_column": "type",
    "sti_name": "Car"
  }
}
```

Both metadata variants are closed schema branches, and the enclosing entity
remains closed. Subtype metadata requires all five shown members, the subtype
entity requires an empty `attributes` array, and both levels reject extra
members. Inheritance is not encoded as an association relationship, preserving
association cardinality, foreign-key, scope, and relationship-ID semantics.

Builder validation enforces constraints that JSON Schema cannot express
conveniently:

- every subtype `parent_entity_id` and `base_entity_id` resolves in the same IR;
- every referenced base has `sti_base` metadata;
- parent and child share the base table; and
- no physical association endpoint refers to an STI subtype.

The digest covers the complete v3 object, including STI metadata.

## Render-plan v3 contract

The render plan adds required `inheritances` but does not republish IR STI
metadata. Each renderer entity gains only a required `entity_kind` discriminator
(`physical` or `sti_subtype`) so the closed schema can enforce artifact node
boundaries without duplicating parent, base, discriminator, or `sti_name`
facts. The builder projects normalized subtype parent metadata into a
serializer-facing edge containing both stable IDs and resolved safe tokens:

```json
{
  "inheritance_id": "inheritances/entities/vehicles/sti/Admin::Car",
  "parent_entity_id": "entities/vehicles",
  "child_entity_id": "entities/vehicles/sti/Admin::Car",
  "parent_safe_token": "VEHICLE",
  "child_safe_token": "ADMIN_CAR"
}
```

Render-plan construction has one fixed sequence:

1. filter the IR entity set for the artifact (`er` drops STI subtypes, `class`
   keeps them);
2. allocate existing uppercase safe tokens over only that filtered set;
3. project inheritances using the resolved entity tokens and then calculate the
   render-plan digest.

This sequence produces the following artifact contract:

| Artifact | Entities | Inheritances | Associations |
|---|---|---|---|
| `er` | `entity_kind: physical` only | empty | existing physical endpoints |
| `class` | physical and `sti_subtype` nodes | all valid STI edges | existing physical endpoints |

Filtering first prevents hidden subtype labels from changing ER safe tokens or
collision diagnostics. The ER schema rejects non-physical entity kinds and
non-empty inheritances. Class validation rejects dangling inheritances.
`RenderPlanBuilder` proves each `sti_subtype` entity has exactly one edge whose
parent came from the IR `metadata.parent_entity_id`; the renderer contract does
not duplicate that IR metadata. Exact ER matrix output independently detects an
unintended extra projected node.

Physical entity labels keep the existing demodulized display behavior. STI
subtype labels use the fully qualified `ruby_constant`. This makes equal
demodulized names visibly distinct.

## Mermaid serialization

The class serializer declares every entity before emitting edges. A labelled
subtype declaration uses Mermaid's documented ID/display-label separation:

```mermaid
class ADMIN_CAR["Admin::Car"]
```

The full deterministic class body order is:

1. entity declarations and their attributes, sorted by `entity_id`;
2. inheritance edges, sorted by `inheritance_id`; and
3. association edges, sorted by `relationship_id`.

Each inheritance is serialized parent first:

```mermaid
VEHICLE <|-- ADMIN_CAR
```

ER serialization does not gain an inheritance path. The serializer validates
the render-plan schema and existing Mermaid text preconditions before producing
text. `SchemaProbe`, `IrBuilder`, and `RenderPlanBuilder` own STI reference
invariants; the serializer does not duplicate that normalization logic.

## Real Rails compatibility matrix

The shared real app adds loaded families for every declared Rails/Ruby pair:

- default discriminator: base, direct child, and grandchild;
- custom `inheritance_column`;
- an abstract boundary whose following concrete class has a new `base_class`
  and therefore does not attach to the earlier selected family; both the
  earlier base and the post-boundary concrete base are selected, and the latter
  has its own concrete STI child in the exact oracles;
- namespaced concrete types with equal demodulized `sti_name` values;
- Ruby inheritance with STI disabled; and
- Ruby inheritance where the physical table has no effective discriminator.

Subtype-only associations are declared in a fixture family and must not appear
in the association oracle.

The matrix task gains checked-in exact STI projections from the class render
plan plus a fixture-owned Rails runtime oracle. The runtime probe is matrix-only
instrumentation; it does not publish IR or put STI metadata back into the
renderer contract:

- `rails_mmd_expected_sti_entities.json` compares projected subtype entity IDs,
  kinds, fully qualified labels, and safe tokens;
- `rails_mmd_expected_inheritances.json` compares inheritance IDs and endpoints;
- `rails_mmd_expected_sti_runtime.json` compares the loaded classes' exact
  `base_class`, table, effective `inheritance_column`, `sti_name`, abstract flag,
  and `descends_from_active_record?` value as observed inside each real app;
- `rails_mmd_expected_core_class.mmd` compares the complete class artifact,
  including fully qualified labels, inheritance order, and unchanged
  associations; and
- `rails_mmd_expected_core_er.mmd` compares the complete ER artifact and proves
  that no subtype entity or inheritance leaks into the physical projection.

The Mermaid files are independent checked-in oracles, not text regenerated from
the render plan under test. The matrix retains its existing self-consistency
check in addition to these exact comparisons. Before artifact validation, the
runner executes a checked-in fixture script under the pair's Rails environment
to write the actual runtime STI projection for comparison.

Matrix integration TDD starts with four explicit red cases: missing class
oracle, missing ER oracle, mismatched class oracle, and mismatched ER oracle.
Only after those fail for the expected reason does `ArtifactValidator` gain the
two independent exact comparisons.

Sensitivity specs prove that removing a subtype, changing its parent or
`sti_name`, introducing a duplicate ER entity, or dropping an inheritance makes
the matrix task fail.

## Public TDD seams and vertical slices

Implementation follows one failing public-seam example at a time. No test may
assert a new private helper.

1. **Schema normalization** — red `SchemaProbe#probe` examples for a direct and
   multi-level true STI family; implement `inventory_records:` and normalized
   `StiSubtype` output.
2. **Normalization boundaries** — red examples for custom column/name,
   namespace collisions, abstract boundaries, disabled/no-column false
   positives, unreadable metadata, and deterministic ordering; complete only
   the safe runtime classifier.
3. **IR v3** — red builder and fixture-backed schema examples for non-STI,
   `sti_base`, and `sti_subtype` metadata branches; implement the smallest v3
   normalized projection and closed schema.
4. **Render-plan v3** — red ER/class projection examples, including
   filter-before-token-allocation, IR-metadata erasure, `entity_kind` artifact
   conditionals, and invalid inheritance references; implement artifact-specific
   entity projection and inheritance safe-token resolution.
5. **Mermaid class output** — red golden for fully qualified declarations,
   multi-level inheritance order, and unchanged association endpoints; add the
   class-only serializer pass.
6. **Generation handoff** — red `Generate` integration proving inventory reaches
   schema probe and publisher output paths remain unchanged; wire the existing
   stages.
7. **Real matrix oracle** — red matrix-task expectations and three-pair fixture
   failures; add exact STI oracles and then fixture families.
8. **Regression closure** — red direct subtype selection, subtype-only
   association, closed-schema invalid fixtures, and oracle mutation examples;
   make only the missing boundary changes.

Each slice records its initial failing command and final passing command in
`implementation.md`.

## Verification-hook isolation slice

P2-01 exposed an independent test-harness defect: when Git invokes `pre-push`,
the inherited repository-discovery environment can cause temporary-repository
spec commits to target the caller's repository. This is repaired as a separate
TDD slice before P2-02 is pushed.

1. Add a red `HookChecks` spec that creates an outer temporary repository, sets
   `GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE`, `GIT_OBJECT_DIRECTORY`, and
   `GIT_ALTERNATE_OBJECT_DIRECTORIES`, then proves the helper's inner init and
   commit affect only the inner repository.
2. In the temporary-repository helper, save, clear, and ensure-restore those
   variables around repository creation and the yielded example.
3. Prove both that the inner repository receives its intended commit and that
   the outer repository HEAD/worktree remain unchanged.
4. Add a deterministic repository instruction: tests that create nested Git
   repositories must isolate repository-discovery variables; until the
   regression is present on a branch, run the pre-push hook directly and use
   `LEFTHOOK=0` only for the transport whose checks have just passed.

The implementation commit and review record treat this as workflow hardening,
not STI runtime behavior.

## File plan

Production and schemas:

- `lib/rails_mmd/generate.rb`
- `lib/rails_mmd/schema_probe.rb`
- `lib/rails_mmd/ir_builder.rb`
- `lib/rails_mmd/render_plan_builder.rb`
- `lib/rails_mmd/mermaid_serializer.rb`
- `schemas/ir.schema.json`
- `schemas/render_plan.schema.json`

Tests and real app:

- `spec/rails_mmd/schema_probe_spec.rb`
- `spec/rails_mmd/ir_builder_spec.rb`
- `spec/rails_mmd/render_plan_builder_spec.rb`
- `spec/rails_mmd/mermaid_serializer_spec.rb`
- `spec/rails_mmd/generate_spec.rb`
- `spec/contracts/schema_spec.rb` and v3 fixtures
- `fixtures/rails_matrix/template/app/models/**`
- `fixtures/rails_matrix/template/db/schema.rb`
- `fixtures/rails_matrix/template/rails_mmd.yml`
- `fixtures/rails_matrix/template/rails_mmd_expected_sti_entities.json`
- `fixtures/rails_matrix/template/rails_mmd_expected_inheritances.json`
- `fixtures/rails_matrix/template/rails_mmd_expected_sti_runtime.json`
- `fixtures/rails_matrix/template/rails_mmd_expected_core_class.mmd`
- `fixtures/rails_matrix/template/rails_mmd_expected_core_er.mmd`
- `fixtures/rails_matrix/template/script/rails_mmd_sti_runtime_oracle.rb`
- `tooling/rails_matrix.rb`
- `spec/integration/rails_matrix_task_spec.rb`

Workflow knowledge:

- `spec/rails_mmd/hook_checks_spec.rb`
- the temporary-repository helper owned by that spec
- `AGENTS.md`
- `docs/p2/02-sti/implementation.md`
- `README.md` schema-version migration table
- `docs/active-record-association-support.md`

## Rejected designs

- **Discover STI in `ModelInventory`:** violates its schema-free boundary and
  forces database behavior into the wrong stage.
- **Use `base_class != model` as the classifier:** produces false positives and
  does not prove a discriminator-backed STI hierarchy.
- **Render subtype entities in ER:** represents one shared table multiple times
  and destabilizes physical association endpoints.
- **Reuse association relationships for inheritance:** invents cardinality and
  foreign-key semantics and couples unrelated contracts.
- **Use `sti_name` as subtype identity:** demodulized names can collide.
- **Query discriminator rows:** output would depend on current data rather than
  loaded application structure.
- **Scan `descendants`:** expands beyond the bounded inventory and makes eager-
  load behavior implicit.

## Design contribution record

| Perspective | Contribution |
|---|---|
| Rails runtime | Schema-probe API, true-STI predicate, safe metadata calls, nearest-visible-parent algorithm, and real-matrix family plan |
| API / contract | Closed v3 metadata union, normalized IR parent source of truth, class-only render-plan inheritance projection, artifact invariants, migration boundary, and safe label syntax |
| TDD / QA | Public-seam red-green slices, mutation-sensitive real-matrix oracles, and isolated Git-environment regression slice |

## Design review record

| Round | Perspective | Findings | Correction |
|---|---|---|---|
| 1 | Rails runtime | None | — |
| 1 | API / contract | Safe-token examples violated the uppercase grammar; render-plan filtering/allocation/projection order was ambiguous; reference validation ownership was duplicated | Corrected examples to existing tokens, fixed the three-step build sequence, and assigned STI reference invariants exclusively to probe/build stages |
| 1 | QA / compatibility | Existing matrix self-consistency could not prove exact Mermaid labels/order or ER subtype exclusion | Added independent checked-in class and ER Mermaid golden files plus exact matrix comparisons |
| 2 | Rails runtime | None | — |
| 2 | API / contract | Class render-plan entities duplicated normalized STI metadata already represented by explicit inheritance edges | Restricted STI metadata to IR and made render-plan inheritances the sole renderer-facing STI structure |
| 2 | QA / compatibility | The planned exact Mermaid comparisons were not yet present in code | Clarified the design-phase boundary and added explicit missing/mismatched class/ER oracle red seams before validator implementation |
| 3 | Rails runtime | None | — |
| 3 | API / contract | Metadata erasure left no schema-level discriminator to reject an orphan subtype node in ER | Added a minimal render-plan `entity_kind` discriminator and artifact-conditional schema rules without duplicating STI relation metadata |
| 3 | QA / compatibility | None | — |
| 4 | Rails runtime | None | — |
| 4 | API / contract | None | — |
| 4 | QA / compatibility | None | — |
