# P2-06 cross-domain / multi-DB research

Status: research complete

## Scope

P2-06 makes Active Record connection and configured-domain boundaries explicit
without reading schema metadata outside the selected domain. The support-table
completion criterion permits either external nodes or diagnostics. This research
selects a diagnostic-first contract and keeps IR/render-plan schema version 4.

The supported cases are:

- one configured domain selecting renderable models from more than one Rails
  connection context;
- ordinary, through, polymorphic, delegated-type, and HABTM declarations whose
  endpoints would cross a connection context;
- declarations whose target is owned by another configured domain;
- independent same-domain models on different contexts when their public entity
  identities do not collide.

P2-06 does not introduce external entities, inspect an unselected model's table,
merge artifacts across domains, or infer a database foreign key across contexts.

## Current behavior and blocking seam

`ModelInventory` already records a redacted, canonical `connection_context_id`
for every inventoriable model. It includes Rails configuration name, role,
shard, adapter, database identifier, host, port, and username. Consequently a
reader/writer role or shard boundary remains a boundary even when both contexts
ultimately address the same physical database.

Before P2-06, `SchemaProbe#probe_domain` returns immediately when selected
records contain two context IDs. The fatal `MULTI_DB_UNSUPPORTED` diagnostic
therefore prevents entity probing, relationship classification, and artifact
publication for the whole domain. This is broader than the support-table
requirement: an unrelated archive model suppresses every valid primary-database
entity and relationship.

Cross-domain targets take a different path. `RelationshipBuilder` cannot find
them in its selected-domain entity index and emits the warning
`DOMAIN_RELATIONSHIP_OMITTED`. That behavior is already partial and schema-safe,
but its precedence relative to a connection boundary was not a P0/P1 contract.

## Runtime evidence

The checked-in probe at
`docs/p2/06-cross-domain-multi-db/probes/connection_boundary_probe.rb` records
only stable facts required by this design. It is intended to run inside every
declared Rails matrix bundle.

Observed directly through the checked-in probe on all three declared matrix
pairs, covering Rails 7.2.3.1 and Rails 8.1.3:

- a cross-connection reflection still resolves `klass`, `foreign_key`, and
  `association_primary_key`;
- schema foreign-key evidence belongs to the queried connection and cannot be
  inferred from the target model's connection;
- concrete models below an abstract connection-owning base inherit that base's
  connection configuration;
- a reader/writer role boundary remains a distinct connection context even when
  both roles point at the same database identifier;
- two connections may expose the same table name, so the current
  `entities/<table_name>` identity can collide;
- connection configuration name and writer/reader role are observable in the
  runtime probe. The existing inventory contract and implementation additionally
  require shard to participate in canonical context identity.

These facts permit structural classification of a boundary but do not authorize
probing the other endpoint through the owner's connection.

The runtime probe intentionally establishes only the direct-reflection and
connection-evidence primitive. The through, polymorphic, delegated-type, and
HABTM expectations below are design inferences from their existing normalized
reflection paths, not additional Rails runtime claims. Focused unit tests must
prove each classifier path, and the real family fixture must exercise their
stable public outcome on every matrix pair. Shard participation likewise comes
from the established `ModelInventory` contract and focused inventory tests; the
probe does not synthesize a sharded application.

## Contract decision

P2-06 uses diagnostics rather than external nodes.

1. `SchemaProbe` probes each selected record using that model's own connection.
   Merely selecting more than one connection context is no longer fatal.
2. A relationship whose selected endpoints have different
   `connection_context_id` values is omitted with the warning
   `CONNECTION_RELATIONSHIP_OMITTED`. It does not block other artifacts and does
   not contribute DB-FK, uniqueness, or nullability evidence to a rendered edge.
3. A target outside the current configured domain remains omitted with
   `DOMAIN_RELATIONSHIP_OMITTED`, even when inventory proves that its connection
   context also differs. Configured-domain authority has precedence and no
   outside-domain schema is read.
4. Multiple contexts with distinct table names are supported in one artifact.
   Same-context relationships render normally; cross-context relationships are
   diagnosed locally.
5. If different selected connection contexts expose the same `table_name`, the
   public v4 entity identity would collide. The domain remains fail-closed with
   `MULTI_DB_UNSUPPORTED`. Its meaning narrows to an unrepresentable multi-DB
   identity collision rather than any multi-context selection.
6. IR and render-plan schema version 4, Mermaid grammar, safe-token grammar, and
   existing entity kinds remain unchanged.

This is a real support increment: valid portions of a multi-DB domain now
publish, every unsupported boundary is explicit, and the one shape that cannot
be represented without an ID migration fails deterministically.

## Boundary precedence

Existing declaration validation continues before connection publication where
it protects safety or Rails meaning:

1. unsafe association names;
2. unresolved or non-renderable constants;
3. explicit exclusion and configured-domain ownership;
4. scoped/unsupported association semantics and invalid specialized bindings;
5. selected endpoint connection-context mismatch;
6. local schema/key evidence and relationship construction.

Consequences:

- an explicitly excluded model never becomes a selected or external endpoint;
- a model selected in the current domain remains local even when another domain
  also lists the same Ruby constant;
- ownership by one or more other domains yields one domain-boundary diagnostic,
  not a guessed destination domain;
- a cross-domain plus cross-context target reports the domain boundary;
- a selected same-domain cross-context target reports the connection boundary;
- one invalid declaration never suppresses valid siblings.

`delegated_type` auto-expansion and STI discovery retain their existing
same-context fences. P2-06 changes the diagnostic reason for a selected
connection boundary; it does not authorize cross-context family expansion or
STI hierarchy synthesis.

## Identity and collision rules

Public physical entity IDs remain `entities/<table_name>`. During schema probe,
before a completed domain result can reach `RelationshipBuilder`, selected
records are grouped by table name. A group is a multi-DB collision only when it
contains more than one distinct connection context. Repeated references to one
context are not a collision. This timing prevents the relationship builder's
table-keyed indexes from overwriting an endpoint before IR validation.

The collision diagnostic must:

- have code `MULTI_DB_UNSUPPORTED`, severity `error`, exit code `2`, phase
  `schema_probe`, and domain scope;
- list only redacted canonical connection context IDs;
- never include passwords, URLs with credentials, DSNs, or exception text;
- block only the affected domain under existing publisher rules.

No connection context is added to public entity or relationship IDs in P2-06.
That avoids byte churn for every existing fixture and reserves an ID migration
for a future explicit contract revision.

## Relationship-family expectations

- Direct `belongs_to`, `has_one`, and `has_many`: compare the two selected entity
  contexts before key binding or DB-FK evidence.
- Through associations: every physical hop must remain within one connection
  context. The first mismatching hop produces one connection-boundary warning
  for the declared association.
- Polymorphic associations: concrete candidates on another selected context are
  omitted as connection boundaries. Same-context candidates in the group remain
  eligible; an empty group retains the existing unresolved-group behavior only
  when no more specific boundary diagnostic was produced.
- `delegated_type`: a declared target on another context is not auto-probed and
  carries the connection-boundary diagnostic; same-context delegates are
  unchanged.
- HABTM: owner, reflected target, and hidden join-table probe must belong to the
  same context. Cross-context HABTM is omitted before join-table metadata is
  interpreted.
- Scoped, STI, composite-key, and specialized-option metadata compose only after
  the boundary is accepted. P2-01 through P2-05 output remains byte-identical for
  single-context domains.

## Acceptance criteria

- A domain containing independent selected models from two contexts publishes
  both entities when table names are distinct.
- Valid same-context relationships in that domain publish unchanged.
- Each same-domain cross-context declaration emits exactly one
  `CONNECTION_RELATIONSHIP_OMITTED` warning and no relationship.
- Cross-domain declarations emit exactly one `DOMAIN_RELATIONSHIP_OMITTED`
  warning and never probe outside-domain schema.
- Same table names on different selected contexts emit one deterministic fatal
  `MULTI_DB_UNSUPPORTED` diagnostic and publish no artifacts for that domain.
- Context IDs are compared exactly after the existing canonical inventory
  normalization. The real matrix probe pins distinct configuration names,
  writer/reader roles, and database identifiers; focused `ModelInventory` tests
  pin the already-public shard dimension without requiring a sharded topology in
  every fixture application.
- A model selected locally and also listed by another configured domain remains
  a local entity and uses the ordinary same-context relationship path; exact
  coverage prevents shared ownership from becoming a false domain omission.
- The new warning has a closed diagnostics-schema metadata shape and exit code
  `0`.
- Existing single-context fixtures keep byte-identical IR-derived render plans,
  Mermaid, relationship projections, and diagnostics.
- A real `cross_domain_multi_db` fixture family exercises the contract on all
  three declared Ruby/Rails pairs with exact entities, relationships,
  diagnostics, Mermaid, and runtime-oracle evidence.
- Unit tests cover direct, through, polymorphic, delegated-type, HABTM, collision,
  redaction, partial-success, shared ownership, exact role/shard identity, and
  diagnostic-precedence paths.

## TDD slices implied by the research

1. Replace the broad schema-probe fatal with collision-only detection and prove
   independent multi-context entity probing.
2. Add the closed connection-boundary diagnostic contract.
3. Omit direct selected cross-context endpoints while preserving same-context
   siblings.
4. Apply the boundary to through, polymorphic, delegated-type, and HABTM paths.
5. Add exact public-schema and fake-harness regression coverage.
6. Add the real matrix family and run every declared pair.

## Alternatives rejected

### External nodes in P2-06

IR v4 accepts only physical and STI-subtype entities, and its builder requires
relationship endpoints to be physical. Render-plan v4 has the same two entity
kinds and both serializers assume an ordinary entity declaration. External
nodes would therefore require a schema-version bump, new entity metadata and
token rules, endpoint validation changes, serializer behavior, and widespread
fixture churn. The support table explicitly permits diagnostics, so that change
is disproportionate to this item.

### Context-qualified public entity IDs

Adding connection context to every ID would remove the same-table collision but
would expose operational topology in stable identifiers and rewrite all current
relationships. P2-06 instead diagnoses the unrepresentable collision.

### Keeping the domain-wide multi-DB fatal

This already existed while P2-06 remained marked unsupported. It cannot express
partial success and suppresses unrelated same-context structure, so it does not
meet the selected completion contract.

## Research review record

The research began with three independent read-only specialist passes:

- Rails/Active Record: reflection resolution, abstract connection bases,
  connection identity, and the absence of cross-connection DB evidence;
- architecture: pipeline seam, public schema cost of external nodes, identity
  collision, determinism, and partial publication;
- QA/acceptance: domain/connection orthogonality, precedence, matrix proof, and
  byte-stability requirements.

Their findings were incorporated into the decision and acceptance criteria
above. The first formal review of this document and probe found three issues:
collision detection had to occur before `RelationshipBuilder`; runtime evidence
had to be separated from family-level design inference; and locally selected
shared ownership needed an executable acceptance criterion. Those points were
corrected. A second Rails, architecture, and QA review returned no findings.

The probe executed successfully on all declared pairs:

- Ruby 4.0.6 / Rails 7.2.3.1;
- Ruby 3.3.12 / Rails 8.1.3;
- Ruby 4.0.6 / Rails 8.1.3.

## Sources

- `docs/active-record-association-support.md`
- `docs/p0-contract.md`
- `lib/rails_mmd/model_inventory.rb`
- `lib/rails_mmd/domain_resolver.rb`
- `lib/rails_mmd/schema_probe.rb`
- `lib/rails_mmd/relationship_builder.rb`
- `lib/rails_mmd/ir_builder.rb`
- `lib/rails_mmd/render_plan_builder.rb`
- `schemas/ir.schema.json`
- `schemas/render_plan.schema.json`
- `schemas/diagnostics.schema.json`
- Rails matrix locks under `fixtures/rails_matrix/bundles/`
