# P2-06 cross-domain / multi-DB design

Status: design complete

## Goal and constraints

Implement the diagnostic-first contract fixed by `research.md`:

- a domain may contain selected models from multiple Rails connection contexts;
- same-context structure continues to render;
- selected cross-context relationships are omitted with
  `CONNECTION_RELATIONSHIP_OMITTED`;
- targets outside the current domain remain `DOMAIN_RELATIONSHIP_OMITTED`;
- different contexts exposing the same public physical entity ID remain a fatal
  `MULTI_DB_UNSUPPORTED` collision;
- public IR and render-plan schema version 4 remain unchanged.

The design must not pass a raw database connection to relationship construction,
read target schema through the owner's adapter, synthesize an external node, or
change any single-context artifact bytes.

## Data-flow overview

```text
ModelInventory
  Record(ruby_constant, table_name, connection_context_id, ...)
      |
DomainResolver
  selected Record objects + all-domain ownership index
      |
SchemaProbe
  collision gate
  Entity(..., connection_context_id)
  JoinTable(..., connection_context_id) [internal only]
  delegated target status/diagnostic
      |
RelationshipBuilder
  selected endpoint classifier
  same-context edges OR one boundary warning
      |
IrBuilder
  duplicate physical-ID invariant guard
  unchanged schema v4 payload
```

`connection_context_id` is an opaque normalized value after inventory. No later
stage parses adapter, database, role, shard, or configuration-name fields.

## SchemaProbe responsibilities

### Collision-only gate

Replace broad `multi_db_diagnostic(domain)` behavior with
`entity_identity_collision_diagnostic(domain)` while retaining the public code
`MULTI_DB_UNSUPPORTED`.

The gate runs before schema reads:

1. group explicitly selected `domain.records` by `table_name`;
2. within each group, collect distinct `connection_context_id` values;
3. retain only groups with at least two contexts;
4. if none exist, probe every record normally;
5. otherwise emit one domain-fatal diagnostic and return an empty domain result.

The diagnostic keeps the existing closed metadata shape:

```json
{
  "domain_id": "core",
  "connection_context_ids": ["<redacted canonical context>"]
}
```

Only contexts participating in a colliding group are included. Raw canonical
IDs are de-duplicated and sorted first, then each element is redacted without a
second de-duplication pass. This preserves the fact that distinct contexts
collided even if redaction maps two values to the same public string. The
message changes from general multi-DB selection to an unrepresentable entity
identity collision. It never includes a raw table name, connection object, DSN,
or exception.

After delegated-type expansion, validate the final entity collection again
before returning `DomainResult`. Existing rules forbid cross-context expansion,
so this is a defensive handoff invariant rather than a second normal diagnostic
path. Any detected collision is converted to the same single domain diagnostic,
and the result carries no entities, join tables, STI subtypes, or families.

### Per-entity probing

With no collision, `probe_domain` removes the current early return and calls
`probe_record` for each selected record. Each model already performs table,
column, primary-key, foreign-key, and index reads through its own Active Record
connection. Independent metadata failures keep their existing model/domain
diagnostics and do not widen into a multi-DB failure.

STI discovery retains `candidate_record_matches_base?` exact context equality.
A cross-context STI descendant is not synthesized and does not create an
association warning.

### Delegated-type precedence

Refactor `delegated_type_target` into this order:

1. explicit exclusion;
2. inventory-record existence;
3. renderability;
4. explicit selection in the current domain;
5. ownership exclusively by other configured domains;
6. exact owner/target connection equality;
7. safe auto-expansion.

An explicitly selected target is still checked against the owner context before
being returned as selected. A mismatch returns:

```text
status: :other_connection
diagnostic_code: CONNECTION_RELATIONSHIP_OMITTED
entity_id: nil
```

A non-local target owned by another configured domain returns
`DOMAIN_RELATIONSHIP_OMITTED` before connection comparison. Shared ownership
that includes the current domain remains local. No cross-context delegate is
schema-probed or auto-expanded.

### Context-qualified hidden join tables

Extend internal `SchemaProbe::JoinTable` with `connection_context_id`. This field
is never projected to IR.

Change join-table probing to consume the already-normalized selected records:

- each request contains `model`, `connection_context_id`, and `table_name`;
- requests are grouped by `[connection_context_id, table_name]`;
- `read_join_table` uses only the declaration owner's connection;
- returned records are sorted by context ID then table name.

This prevents two databases' identically named hidden join tables from being
collapsed before relationship classification.

## RelationshipBuilder endpoint seam

Add one internal result envelope and one `DomainContext` operation:

```ruby
Endpoint = Struct.new(:entity, :diagnostic_code, keyword_init: true)

def selected_endpoint(source_entity, target_constant)
  target = entity_by_constant[target_constant]
  return Endpoint.new(diagnostic_code: 'DOMAIN_RELATIONSHIP_OMITTED') unless target
  unless source_entity.connection_context_id == target.connection_context_id
    return Endpoint.new(diagnostic_code: 'CONNECTION_RELATIONSHIP_OMITTED')
  end

  Endpoint.new(entity: target)
end
```

The helper accepts only normalized entities. It does not resolve constants,
inspect reflections, create diagnostics, or access Active Record connections.
Callers first preserve family-specific name, resolution, and renderability
rules, then convert the result's diagnostic code through the existing `omitted`
builder. This yields exactly one diagnostic subject for the declared
association.

Add `same_connection_context?(left, right)` as a small nil-safe primitive for
candidate paths that already hold two selected entities. Add a defense-in-depth
guard to `db_foreign_key?` returning `false` unless both entities share a
context, although construction must normally reject such endpoints earlier.

## Diagnostic contract

Add `CONNECTION_RELATIONSHIP_OMITTED` everywhere the catalog is closed:

- default severity `warning`;
- default exit code `0`;
- phase `relationship_build`;
- scope `relationship`;
- attachment `diagnostics JSON`;
- publication effect `omit relationship`;
- existing `metadata_shape_association`.

The metadata contains domain ID, owner constant, safe association name, and
target constant when known. It deliberately excludes connection-context IDs and
configuration fields. Diagnostic IDs remain deterministic through the existing
canonical metadata hashing.

`MULTI_DB_UNSUPPORTED` retains severity `error`, exit code `2`, phase
`schema_probe`, domain scope, and blocking publication effect, but its documented
condition narrows to a cross-context public entity-ID collision.

## Precedence common to every family

The observable order is:

1. sanitize association name;
2. resolve reflection target and map reader failures to the existing code;
3. reject a non-renderable target;
4. find the target in the selected domain;
5. reject a connection-context mismatch;
6. apply scope/shape/specialized-binding rules;
7. read normalized column/index/FK/join metadata;
8. build and canonicalize the relationship.

Thus:

- unselected targets are domain omissions even when their inventory context
  differs;
- locally selected shared ownership uses the ordinary local path;
- a selected cross-context target never reaches key readers or DB evidence;
- existing unsafe/unresolved/non-renderable diagnostics remain more specific;
- a sibling declaration is unaffected.

Explicit exclusion is resolved before the builder and remains stronger than
local/external classification. Scoped metadata composes only after the endpoint
passes the boundary; an omitted connection relationship is not additionally
reported as scoped.

## Family-specific integration

### Direct belongs-to and has associations

In `build_reflection` and `build_direct_reflection`, call `selected_endpoint`
immediately after target resolution, renderability, and current-domain lookup.
Only a successful endpoint may call `key_columns`, `direct_key_columns`, column
presence checks, `relationship_for`, or `direct_relationship_for`.

Cover `belongs_to`, `has_one`, and `has_many`. Reflection key readers and DB
evidence fakes raise if invoked for a rejected endpoint, proving the gate is
early enough.

### Through

`through_entities` owns the boundary walk because it already resolves every
semantic hop. Maintain a cursor beginning at the declaration owner. For each
hop:

1. resolve and validate the model;
2. call `selected_endpoint(cursor, target_constant)`;
3. emit the declared association's domain/connection code on failure;
4. append the entity and advance the cursor.

Only a complete same-context chain may call
`through_physical_key_omission_code`. That physical-hop walk must independently
call the same selected-endpoint classifier for every hop before
`direct_hop_key_omission_code` reads key binding. This defense is required when
a nested or typed source's semantic chain and normalized physical hop list
differ. The first mismatch returns `CONNECTION_RELATIONSHIP_OMITTED` for the
declared association. Direct-hop key checks remain a later structural
validation. Nested and typed source paths use the semantic terminal selected by
P2-05.

### Polymorphic

In `polymorphic_candidate_diagnostic`, after renderability and before inverse
binding, compare `root.owner` with `candidate.owner`. A mismatch produces one
`CONNECTION_RELATIONSHIP_OMITTED` diagnostic whose owner/name identify the root
declaration and whose target is the concrete candidate.

Same-context candidates in the group remain eligible. If no candidates remain
and at least one `DOMAIN_RELATIONSHIP_OMITTED` or
`CONNECTION_RELATIONSHIP_OMITTED` diagnostic was emitted, do not append
`ASSOCIATION_POLYMORPHIC_TARGETS_UNRESOLVED`. Existing non-boundary candidate
failure behavior remains unchanged.

For an inverse declaration not handled by a root, add a read-only classifier:
sanitize the name, resolve and validate the ordinary holder target, then call
`selected_endpoint` from the inverse owner. A missing selected holder is a
domain omission and a selected holder on another context is a connection
omission. Same-context inverses and cases where a target cannot be safely
established retain `ASSOCIATION_POLYMORPHIC_OMITTED`; no edge is synthesized
without a selected root.

### Delegated type

`SchemaProbe` hands a cross-context declared delegate to
`delegated_target_candidate` with the new diagnostic code and no entity ID. The
builder returns that diagnostic before inverse lookup, referenced-key binding,
or column checks. When all delegates are connection omissions, suppress the
generic unresolved-group diagnostic using the same boundary rule as ordinary
polymorphism.

### HABTM

In `build_habtm_reflection`, call `selected_endpoint` after renderability and
before `habtm_keys`. A rejected endpoint never makes the builder interpret or
lookup normalized join-table/key metadata, and the target connection is never
queried. `SchemaProbe` may already have read the hidden table through the
declaration owner's connection before relationship classification.

For an accepted endpoint, replace `join_table_by_name` with
`join_table_by_context_and_name` and fetch by
`[owner.connection_context_id, join_table_name]`. Endpoint equality guarantees
the reflected target has the same context. Ordinary hidden-table validation and
canonical many-to-many identity remain unchanged.

## IR defense-in-depth

At the start of `IrBuilder#payload_without_digest`, compute physical entity IDs
and call the existing `ensure_unique_ids!` with label `physical entity_id`
before `validated_sti_subtypes` can convert entities to a hash. This is not a
recoverable user diagnostic: normal collisions were already classified by
`SchemaProbe`. It catches an invalid internal handoff and prevents silent entity
overwrite.

No context ID enters IR, render plans, safe-token inputs, Mermaid labels, or
relationship IDs.

## Determinism and partial success

- Collision context IDs are `uniq.sort` before sanitization; sanitized duplicates
  remain as distinct array positions.
- Domain results preserve configured-domain order.
- Entity, join-table, relationship, and diagnostic projections retain their
  existing stable sorts.
- Multiple candidate paths that describe one physical relationship retain the
  existing physical-key canonicalization.
- Direct, through, unhandled inverse, and HABTM declarations with one resolved
  target emit one boundary warning. Polymorphic/delegated roots emit one warning
  per rejected concrete target candidate because each candidate represents a
  distinct potential edge; duplicate paths to the same target are de-duplicated
  by diagnostic identity. Mixed and all-rejected groups retain sorted
  target-specific warnings and do not add a generic unresolved warning.
- A collision-free multi-context domain publishes all selected entities and only
  same-context relationships.
- A collision domain is blocked by existing publisher rules while unaffected
  selected domains may still publish.

## TDD vertical slices

Implementation must use the repository's TDD workflow and preserve each RED
failure before the corresponding GREEN change.

1. **Diagnostic contract**: reject then accept the new catalog code and exact
   association metadata; prove no context details leak.
2. **Collision-only schema probe**: distinct tables across contexts probe and
   publish; identical table IDs across contexts return the narrowed fatal.
3. **Direct boundaries**: cover all three direct macros, shared ownership,
   cross-domain precedence, early key-reader non-invocation, and same-context
   byte behavior.
4. **Through boundaries**: cover first, intermediate, and terminal mismatches,
   nested/typed paths, and one-warning behavior.
5. **Polymorphic/delegated boundaries**: cover mixed candidates, all-rejected
   groups with at least two rejected targets, candidate-warning de-duplication,
   explicit vs expanded delegates, ownership precedence, and no generic warning
   after a boundary warning.
6. **HABTM context isolation**: cover early boundary rejection and two contexts
   with the same hidden join-table name.
7. **IR handoff guard**: reject duplicate physical IDs before STI/hash handling.
8. **Harness and matrix**: add the real family, probe validator, exact public
   oracles, fake collision/role/shard cases, and legacy byte-equivalence checks.

Focused unit doubles may expose arbitrary normalized context IDs or raise when a
forbidden reader is reached. The user has pre-approved these test seams.

## Real matrix fixture design

Add fixture family `cross_domain_multi_db` for every declared pair. It uses two
SQLite database configurations and abstract application/archive bases. The
successful `core` domain includes:

- a same-context relationship that must render;
- independent archive and primary entities with distinct table names;
- a selected cross-context direct declaration that must be diagnosed;
- a target selected locally and also listed in another configured domain;
- a target owned only by another domain to prove domain precedence;
- a through chain whose intermediate or terminal crosses context;
- a polymorphic root with one same-context and at least two cross-context
  concrete candidates;
- a delegated-type root with same-context and cross-context declared types;
- a cross-context HABTM declaration with a hidden join table visible from only
  the declaration-owner context.

All listed family cases are mandatory on all three pairs; none is replaced by a
unit double. A unit-only exception requires a checked-in Rails declaration
probe proving the path cannot be expressed by a real model.

The collision case is isolated as a second family scenario so its fatal exit
cannot hide the successful scenario's exact artifacts. The matrix runner invokes
the collision config separately on every pair and asserts exit `2`, empty
stdout, exact sanitized diagnostics, absence of the affected domain's Mermaid
and render-plan artifacts, and absence of connection secrets. Focused
schema-probe/generate tests provide cheaper failures, but do not replace the
three-pair public scenario. A small fixture-owned runtime oracle records stable
booleans and normalized reader values; it never writes temporary database paths
to an expected artifact.

Wire the checked-in research probe through `PAIR_PROBES` with a closed validator.
The validator compares Rails version, both reflection readers, writer/reader
context distinction, cross-database evidence absence, and same-table collision
facts. It ignores no unknown keys and reports the selected pair on mismatch.

Exact fixture evidence includes:

- Mermaid ER and class text;
- diagnostics array;
- relationship projection;
- entity IDs/kinds/labels;
- polymorphic/delegated projections where present;
- runtime oracle;
- process exit and publication behavior through the integration harness.

Existing default, delegated-type, composite-key, and specialized-options family
oracles must remain unchanged on all three pairs.

## Documentation and durable guidance

Update:

- `docs/p0-contract.md` for multi-context selection, collision-only fatal,
  connection omission, precedence, and exit/publication rules;
- `docs/active-record-association-support.md` to mark P2-06 supported;
- `docs/p2/06-cross-domain-multi-db/implementation.md` with RED/GREEN/review and
  verification evidence;
- `AGENTS.md` only if implementation reveals a reusable invariant not already
  captured by the P1/P2 engineering-record routing.

Candidate durable invariant: relationship construction consumes opaque normalized
connection identity only; schema reads stay with `SchemaProbe` and hidden
connection-owned metadata must be keyed by both context and local name.

## Design review record

Three independent design inputs were collected before this document:

- Rails: family-specific gate placement, reflection-reader safety, delegated/STI
  fencing, and context-qualified HABTM probing;
- architecture: collision gates, normalized handoff, IR invariant guard,
  responsibility boundaries, and partial publication;
- QA/test: precedence table, vertical TDD slices, exact-oracle scope, redaction,
  and matrix/fake-harness separation.

Formal design-review iterations are appended after specialist review of this
integrated document. The first integrated review found six issues: collision
contexts had to be de-duplicated before redaction; physical through hops needed
their own early boundary gate; polymorphic generic-warning suppression had to
cover both domain and connection boundaries; unhandled inverse declarations
needed safe boundary classification; HABTM's pre-builder probe guarantee needed
precise wording; and polymorphic warning granularity plus real-matrix coverage
were under-specified. The design now fixes candidate-specific warning identity,
requires every association family in the real fixture, and runs the fatal
collision as an independent scenario on all three pairs. A second Rails,
architecture, and QA review returned no findings.
