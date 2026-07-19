# P2-03 Delegated Type Research

Status: complete

## Product boundary

The support matrix defines P2-03 as Active Record `delegated_type`, complete
when the delegator and concrete types are drawn. P2-03 must compose with scoped
relationship metadata and STI support already delivered, while leaving these
later items unchanged:

- composite primary/foreign keys and `query_constraints` (P2-04);
- `primary_key`, `source`, `source_type`, and specialized `as` resolution
  (P2-05);
- cross-domain and multi-database publication (P2-06);
- behavioral options including `dependent`, `touch`, and `counter_cache`
  (P2-07).

## Verified Rails facts

Rails 7.2.3.1 and 8.1.3 implement `delegated_type` in two steps:

1. declare a polymorphic `belongs_to` for the role;
2. define role-specific methods and scopes from the supplied `types:` list.

The reflection is therefore indistinguishable from an ordinary polymorphic
`belongs_to` by `macro`, `polymorphic?`, and `options` alone. In particular,
the declared type list is not stored in `reflection.options`. Rails exposes it
through the generated class method `<role>_types`.

Both supported Rails versions generate that method in
`active_record/delegated_type.rb`, and both return a string copy of the declared
list. A plain polymorphic `belongs_to` does not generate the method. The local
pinned-runtime probe observed:

```text
Rails 7.2.3.1: options={polymorphic: true}, keys=entryable_id/entryable_type,
types=["Message", "Access::Notice"], source=delegated_type.rb:242
Rails 8.1.3:   options={polymorphic: true}, keys=entryable_id/entryable_type,
types=["Message", "Access::Notice"], source=delegated_type.rb:242
plain polymorphic belongs_to: <role>_types absent
```

Rails does not constantize the declared strings while defining the macro.
Unknown names can therefore survive application boot. Namespaced strings are
supported. The generated convenience scopes use
`type.tableize.tr("/", "_")`, but diagrams need the canonical model constant,
not a generated convenience-method name.

Delegated types are composition, not Ruby inheritance. The delegator and each
delegate use real physical tables. Rails polymorphic storage uses a model's
`base_class` name; an STI leaf is consequently not a new physical delegated
endpoint.

## Current repository behavior

`RelationshipBuilder` already publishes direct polymorphic roots as one
target-specific edge per selected matching inverse `has_one`/`has_many ...,
as:` reflection. It already provides:

- deterministic relationship identity;
- holder `(type, id)` key validation;
- conservative cardinalities with inverse/unique-index evidence;
- selected same-domain endpoints;
- scope metadata without executing a scope proc;
- exact diagnostics for unresolved, non-renderable, missing-column, and
  unsupported-key shapes.

That path intentionally excluded delegated types in P1-06. Treating a
delegated type as generic polymorphism has two observable defects:

1. a valid delegated type with no inverse declaration produces no concrete
   edges even though `types:` is authoritative;
2. a matching inverse whose model is not in `types:` can be published even
   though it is not a declared delegate.

IR v3, render-plan v3, and both Mermaid serializers already represent the
required physical nodes and concrete relationships. P2-03 does not require a
schema version bump, a synthetic entity kind, a new public relationship kind,
or new Mermaid syntax.

## Accepted research boundary

The recommended P2-03 contract is:

- Detect a delegated root only when the selected owner has a direct
  polymorphic `belongs_to` and its `<role>_types` method is Rails-generated.
  Before calling it, compare the method's source file with the source file of
  the active runtime's `ActiveRecord::DelegatedType` implementation. This avoids
  a hard-coded gem path or line number while ensuring an arbitrary application
  method is not executed as feature discovery. The supported matrix is pinned
  to Rails 7.2.3.1 and 8.1.3; a failed provenance check falls back to ordinary
  inverse-driven polymorphism.
- Treat the generated type list as the authoritative whitelist.
- Expand renderable declared delegate records into the delegator's domain when
  they use the same connection context and have not been explicitly excluded.
  This is a deliberate P2-03 exception to P0 selected-entity-only probing: the
  delegator selects its declared physical family. Carry resolved exclusion
  intent beyond `DomainResolver` so this expansion cannot defeat an explicit
  `exclude_models` entry.
- Do not expand a delegate that is selected only in another configured domain,
  or one with a different connection context. Keep those relationships on the
  existing `DOMAIN_RELATIONSHIP_OMITTED` path until P2-06 defines external
  nodes/cross-domain edges. A target already selected in the delegator's domain
  remains an ordinary selected entity even if another domain also selects it.
- Make that boundary executable through a normalized
  `ruby_constant -> configured domain IDs` ownership index derived from every
  configured domain's include-minus-exclude lists, independent of a CLI
  `--domain` filter. `DomainResolver` passes this index with resolved exclusion
  intent; `Generate` passes both to `SchemaProbe`. Full inventory alone is not
  sufficient to distinguish an unowned type from a type configured elsewhere.
- Perform declaration discovery and safe family expansion in `SchemaProbe`,
  which already owns full-inventory STI expansion and the selected-connection
  guard. Pass only normalized delegated-family metadata and probed entities to
  `RelationshipBuilder`; do not add raw database access there.
- Mark auto-expanded entities separately from explicitly selected entities.
  They may be delegated-edge targets and may supply an optional matching inverse
  as cardinality/scope evidence, but their unrelated direct, through, HABTM, or
  polymorphic associations are not inventoried. They do not recursively expand
  their own delegated families. If the delegate was explicitly selected in the
  same domain, it remains a normal association owner and can expand its family.
- Publish one existing-shape polymorphic edge for each surviving declared
  target even when no inverse reflection exists.
- Use a matching inverse only as optional evidence for singular cardinality
  and scoped metadata. It is not candidate-discovery authority.
- Exclude undeclared inverse candidates. Leave an otherwise unhandled
  polymorphic inverse on the existing deterministic omission path.
- Preserve existing relationship IDs and public shapes for already-working
  delegated families so P2-03 is backward compatible with P1-06 artifacts.
- Keep default scalar `<role>_id` / `<role>_type` keys only. Explicit custom or
  composite key options stay on the existing omission paths until P2-04/P2-05.
- Resolve STI leaf declarations as non-renderable concrete endpoints rather
  than expanding associations to subtype nodes. P2-02 keeps association
  endpoints physical.

This interpretation is stricter than relabeling generic polymorphism as
delegated-type support. It draws the physical family selected through the
delegator, supports valid Rails models without inverse concerns, and retains
explicit exclusion and cross-domain authority.

## Alternatives considered

### Require matching inverse declarations

Rejected as the primary contract. It reuses the P1-06 implementation but fails
valid Rails declarations where `types:` exists without a reverse association.
It also makes the inverse, rather than Rails' declared whitelist, authoritative.

### Require every delegate model to be selected separately

Rejected as the product contract. A configuration that selects the delegator
but cannot draw its declared concrete family does not satisfy the support-row
completion condition. Family expansion must nevertheless preserve explicit
exclusions, connection guards, and a target's explicit assignment to a
different configured domain.

### Add delegated-type nodes or public metadata

Rejected. The delegator and delegates already exist as ordinary physical
entities. Existing concrete relationship edges fully express the support-matrix
completion condition without a public schema change.

## Acceptance and failure matrix

Required positive cases:

- selecting only the delegator expands two declared same-connection physical
  types and produces two deterministic concrete edges, with or without inverse
  declarations;
- a selected namespaced type is resolved by its full constant and remains
  distinct from another namespace with the same leaf name;
- declaration order, reflection order, and selection order do not change edge,
  group, diagnostic, or Mermaid ordering;
- a scope proc on the root or canonical inverse is never executed and marks the
  published edge `metadata.scoped: true`;
- a matching `has_one` inverse or total unique `(type, id)` index preserves the
  existing singular-cardinality rule.

Required partial/negative cases:

- an otherwise matching inverse not present in `types:` is not published;
- an auto-expanded delegate's unrelated association and nested delegated family
  are not published; selecting that delegate explicitly enables its ordinary
  owner behavior without changing the parent delegated edge;
- an ordinary polymorphic root with an application-defined `<role>_types`
  method is not misdetected and that method is not executed;
- an unresolved declared type emits `ASSOCIATION_TARGET_UNRESOLVED`;
- an abstract, non-Active-Record, or STI-leaf declared type emits
  `ASSOCIATION_TARGET_NOT_RENDERABLE_OMITTED`;
- an explicitly excluded, other-domain-owned, or different-connection declared
  type emits `DOMAIN_RELATIONSHIP_OMITTED`;
- if no declared type survives, emit exactly one
  `ASSOCIATION_POLYMORPHIC_TARGETS_UNRESOLVED` root warning in addition to any
  target-specific omission evidence;
- an empty `types:` list does not crash and produces the same zero-target root
  warning;
- custom scalar or composite delegated keys remain unsupported and do not
  partially publish;
- ordinary polymorphic associations retain their inverse-driven behavior.

## TDD and real-Rails evidence seams

- `DomainResolver` and `SchemaProbe` public specs should prove exclusion-intent
  handoff, the all-configured-domain ownership index, family expansion,
  same-connection/other-domain guards, entity origin, normalized metadata, and
  provenance-based rejection of a spoofed `<role>_types` method.
- `RelationshipBuilder` public specs should prove normalized-whitelist use,
  no-inverse publication, inverse filtering, scope non-execution, optional
  cardinality evidence, partial success, zero-target diagnostics, and the fence
  against unrelated associations owned by auto-expanded delegates.
- Contract fixtures should remain unchanged unless implementation proves a
  public-shape change is necessary.
- The shared real Rails app should include a delegated family with namespaced
  same-leaf delegate classes, at least one no-inverse declared target, one
  undeclared inverse, and a scope proc that raises if executed.
- Existing exact relationship, polymorphic-group, diagnostic, class Mermaid,
  and ER Mermaid oracles should prove end-to-end behavior and exact
  target-specific diagnostic codes on every declared Ruby/Rails pair.
- A small fixture-owned runtime oracle should prove that the detected
  `<role>_types` values and source file are consistent across the matrix without
  publishing new runtime metadata from rails-mmd.

## Risks

- Executing an arbitrary `<role>_types` method would violate the tool's
  reflection-only safety boundary. Provenance comparison with the active
  `ActiveRecord::DelegatedType` implementation is required before the generated
  method is called; a spoofing regression must prove that presence alone is
  insufficient.
- A user override of Rails' generated method is intentionally treated as
  ordinary polymorphism. That loses delegated specialization but avoids running
  arbitrary code.
- `store_full_class_name = false` can make namespaced polymorphic values
  ambiguous. P2-03 should not invent demodulized target matching; unresolved
  cases remain diagnostic.
- A declared target can resolve as a Ruby constant but still be excluded,
  assigned to another domain, on another connection, or non-renderable. These
  states must not create external nodes before P2-06.

## Research review record

| Round | Perspective | Finding | Correction |
|---|---|---|---|
| 1 | Architecture | Requiring every delegate to be selected separately weakened the support-row completion condition | Added delegator-driven family expansion with explicit exclusion and connection guards |
| 1 | Architecture | A hard-coded generated-method source path would couple detection to gem layout | Compare provenance with the active runtime `DelegatedType` implementation and fall back to ordinary polymorphism |
| 1 | QA / compatibility | Spoofed `<role>_types` and target-specific omission diagnostics were not exact acceptance cases | Added the non-execution spoof case and fixed public diagnostic codes/oracles |
| 2 | Architecture | Full inventory cannot distinguish unowned types from types configured in another domain | Added an all-configured-domain constant ownership index to the normalized handoff |
| 2 | QA / compatibility | Auto-expanded entities could unintentionally publish unrelated associations | Added explicit/expanded entity origins and a non-recursive owner-inventory fence |
| 3 | Rails runtime, architecture, QA / compatibility | No findings | None |

## Sources

- [Rails 7.2.3.1 DelegatedType API](https://api.rubyonrails.org/v7.2.3/classes/ActiveRecord/DelegatedType.html)
- [Rails 8.1.3 DelegatedType API](https://api.rubyonrails.org/v8.1/classes/ActiveRecord/DelegatedType.html)
- [Rails 7.2.3.1 delegated_type source](https://raw.githubusercontent.com/rails/rails/v7.2.3.1/activerecord/lib/active_record/delegated_type.rb)
- [Rails 8.1.3 delegated_type source](https://raw.githubusercontent.com/rails/rails/v8.1.3/activerecord/lib/active_record/delegated_type.rb)
- [Rails association guide: delegated types](https://guides.rubyonrails.org/association_basics.html#delegated-types)
- `lib/rails_mmd/relationship_builder.rb`
- `docs/p1/06-polymorphic-associations/{research,design,implementation}.md`
- `docs/p2/02-sti/{research,design,implementation}.md`
