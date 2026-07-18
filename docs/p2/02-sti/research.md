# P2-02 Single-Table Inheritance Research

Status: specialist research review complete

## Target

Define deterministic display rules for a selected Active Record STI base and
its loaded derived classes without duplicating one physical table in ER output
or destabilizing existing association identity.

## Rails facts

- Rails STI uses `inheritance_column` to discriminate subclasses. Base-class
  rows may store `nil`; the column is `type` by default and may be changed or
  disabled. A Ruby subclass alone does not prove that the table uses STI.
- `base_class` returns the first concrete class below `ActiveRecord::Base` or an
  abstract superclass. Marking a class abstract removes it from that STI
  hierarchy and changes table-name/base-class derivation for the next concrete
  class.
- `descends_from_active_record?` is the public predicate that reflects whether a
  class needs an STI type condition. It checks the inheritance column, whereas
  `base_class != model` alone does not.
- After rails-mmd's Rails boot/eager-load stage succeeds, named loaded
  descendants are observable before inventory. `descendants` still contains
  loaded classes only; incomplete eager loading is an environment failure, and
  rails-mmd must never inspect rows to guess unloaded or stale type values.
- `sti_name` is the exact discriminator value for a loaded subclass. With the
  default `store_full_sti_class` and `store_full_class_name`, it is fully
  qualified; disabling either setting demodulizes it.
- `polymorphic_name` is based on `base_class`, not the concrete STI subclass.
  Reflection metadata therefore cannot prove a concrete polymorphic subtype
  from the stored polymorphic type alone.
- Rails 7.2.3.1 and 8.1.3 implement the relevant `base_class`,
  `abstract_class?`, `descends_from_active_record?`, `sti_name`, and
  `polymorphic_name` rules equivalently.

Primary sources:

- [Rails 8.1 ActiveRecord::Inheritance](https://api.rubyonrails.org/classes/ActiveRecord/Inheritance.html)
- [Rails 8.1 inheritance class methods](https://api.rubyonrails.org/classes/ActiveRecord/Inheritance/ClassMethods.html)
- [Rails 7.2 inheritance source](https://raw.githubusercontent.com/rails/rails/v7.2.3.1/activerecord/lib/active_record/inheritance.rb)
- [Rails 8.1 inheritance source](https://raw.githubusercontent.com/rails/rails/v8.1.3/activerecord/lib/active_record/inheritance.rb)
- [Rails model schema inheritance column](https://api.rubyonrails.org/classes/ActiveRecord/ModelSchema.html)

## Repository facts

- P0 intentionally marks a record non-renderable when `base_class != model`.
  Explicitly including or excluding such a record produces
  `DOMAIN_MODEL_NOT_RENDERABLE` with reason `sti_subclass`.
- `ModelInventory` is schema-free. Moving inheritance-column inspection there
  would violate the stage boundary recorded in `docs/p0-contract.md`.
- `SchemaProbe` is the first stage allowed to observe columns and selected model
  runtime schema behavior. It already returns normalized records rather than raw
  connections to later stages.
- P2-02 must extend the schema-probe handoff explicitly: domain resolution keeps
  producing selected base records, while schema probe additionally receives the
  schema-free inventory records. It may resolve candidate descendant models and
  inspect the selected base schema, but it must not probe every descendant as a
  second physical table.
- Base entity and association identity are physical-table based:
  `entities/<table>` and relationship physical keys use those IDs. Treating
  every STI subclass as an ordinary entity would collide or require a global
  relationship identity rewrite.
- IR and render-plan entity objects are closed v2 objects. Structured STI data
  requires an IR/render-plan schema bump to v3; config and diagnostics can
  remain v1.
- ER and class serializers currently consume the same entity list, but only a
  class diagram has an inheritance relation. Existing tests deliberately reject
  inheritance syntax because it was outside P0/P1.
- Relationship discovery iterates only selected probed base entities. It does
  not observe associations declared only on an STI subclass.

## Evaluated representation options

### Ordinary subtype entities everywhere

Give every subclass full columns and association endpoints in both formats.

Rejected because one physical table would be duplicated in ER, table-based IDs
would collide, inherited reflections would duplicate edges, and association
canonicalization would require a cross-cutting rewrite.

### Base entity with metadata only

Keep one entity and attach a list of subclass constants without rendering
subtype nodes.

Rejected as the P2-02 completion rule requires a visible, deterministic rule for
both base and derived classes. Metadata alone would preserve the P0 omission in
the user-facing class diagram.

### Hybrid physical/logical projection

Keep the current base entity as the only physical association endpoint. Add
synthetic subtype entities under the base identity namespace for structured
class-view projection, and derive class inheritance edges from closed STI
metadata. ER filters synthetic subtypes; class output retains them.

Recommended because existing base entity IDs, relationship IDs, attributes, and
ER semantics remain stable while the class view gains explicit inheritance.

## Recommended minimum P2-02 boundary

- A selected renderable base class automatically exposes every eager-loaded,
  named, concrete descendant in the same true STI family.
- Determine a true family only in the schema-observing stage: the candidate has
  the selected base as `base_class`, has the same effective
  `inheritance_column` as that base, and needs an STI type condition. Do not use
  `base_class != model` alone as proof. Per-descendant discriminator-column
  overrides are outside P2-02.
- Preserve `entities/<base_table>` for the base. Give each subtype a stable
  synthetic ID derived from the base entity ID and the fully qualified Ruby
  constant, never from `sti_name` alone.
- Normalize, without evaluating queries or reading rows:
  `base_entity_id`, `parent_entity_id`, `ruby_constant`, `inheritance_column`,
  and exact `sti_name`. `parent_entity_id` points to the nearest accepted
  concrete ancestor in the same selected family. An abstract superclass starts
  a new Rails `base_class` boundary for the next concrete class, so a concrete
  descendant across that boundary is not reattached to the earlier selected
  base and neither node is projected for that family.
- IR v3 contains the base entity plus subtype entities with closed STI metadata.
  Shared attributes remain on the base; subtype attributes are empty.
- ER render plans contain the base physical entity only. Class render plans
  contain the base and subtype nodes and serialize each immediate-parent edge as
  Mermaid inheritance (`PARENT <|-- CHILD`).
- Supported association edges remain anchored to the base entity. Inherited or
  subclass-only association expansion is not inferred in P2-02.
- Explicit `include_models` or `exclude_models` entries naming a subtype retain
  the existing `DOMAIN_MODEL_NOT_RENDERABLE` diagnostic. Family visibility is
  controlled by selecting its base.
- Namespaced subtype identities and class labels use the fully qualified Ruby
  constant, even when `sti_name` is demodulized. Non-default
  `inheritance_column` and `sti_name` settings are observable without row access
  and use the same normalized contract. Equal demodulized `sti_name` values do
  not collapse distinct fully qualified subtype IDs.

## Explicit exclusions

- Reading persisted discriminator values or diagnosing unknown/stale type rows.
- Discovering descendants that Rails eager loading did not load.
- Expanding direct, through, HABTM, or polymorphic associations to subtype
  endpoints.
- Inferring a concrete STI subtype from a polymorphic type column.
- Treating abstract classes as visible subtype nodes.
- Repurposing `docs/p0-contract.md`; it remains the P0 baseline.

## Required verification boundaries

- Unit and real Rails matrix: distinguish true STI from a Ruby subclass with
  STI disabled or no inheritance column; the negative family produces no
  synthetic subtype or inheritance edge.
- Unit: one-level, multi-level, namespaced, custom-column, and demodulized
  `sti_name` normalization is deterministic and never reads rows.
- Unit and real Rails matrix: an abstract boundary and its new concrete family
  are excluded from the earlier selected base. The matrix separately selects
  the post-boundary concrete base and proves its own concrete subtype/edge;
  immediate accepted parent IDs remain valid in both selected families.
- Contract: fixture-backed IR/render-plan v3 negatives reject missing required
  STI members, malformed types, extra members, and subtype metadata in an ER
  artifact. Builder/serializer tests reject a class inheritance reference that
  has no matching subtype metadata.
- Projection: ER has exactly one shared-table entity; class output has base and
  empty-attribute subtype nodes plus immediate inheritance edges.
- Regression: existing relationship IDs and endpoints remain the base physical
  entity; subtype-only association declarations do not silently create edges.
- Selection: explicitly selecting/excluding a subtype keeps the existing closed
  domain diagnostic.
- Real Rails: default one-level/multi-level, custom-inheritance-column, STI-
  disabled negative, and namespaced demodulized-name collision families pass all
  three matrix pairs with exact structured and Mermaid oracles.
- Sensitivity: removing one subtype, changing its parent, changing `sti_name`,
  or adding a duplicate ER entity makes the matrix task fail.

## Research contribution record

| Perspective | Contribution | Disposition |
|---|---|---|
| Rails runtime | Distinguished true STI from Ruby inheritance; documented loaded-descendant, `sti_name`, abstract, and polymorphic base-name behavior | Accepted |
| Architecture | Identified table-ID/association coupling and proposed a hybrid ER/class projection with base-only association endpoints | Accepted |
| QA / compatibility | Mapped current negative seams, matrix reuse, row-inspection exclusions, and subtype-association risk | Accepted; metadata-only/base-only display was rejected because it would not visibly represent derived classes |

## Research review record

| Round | Perspective | Findings | Correction |
|---|---|---|---|
| 1 | Rails runtime | Persisted base rows, per-class discriminator rules, custom settings, and eager-load guarantees were overstated or under-tested | Clarified nil base discriminators, required matching effective columns, bounded eager-load visibility, and added custom/demodulized matrix families |
| 1 | Architecture | Descendant handoff, abstract-parent references, and namespaced display identity were underspecified | Added inventory-to-schema-probe input, nearest visible parent semantics, and fully qualified subtype display/identity |
| 1 | QA / compatibility | Matrix lacked false-positive STI, duplicate demodulized-name, and fixture-backed closed-schema negatives | Added exact negative/collision families and explicit invalid STI metadata requirements |
| 2 | Rails runtime | None | — |
| 2 | Architecture | None | — |
| 2 | QA / compatibility | None | — |
