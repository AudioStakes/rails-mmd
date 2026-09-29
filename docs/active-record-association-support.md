# Active Record association support (Rails 7.2 / 8.1)

The target Rails series are 7.2 and 8.1. "Supported" describes behavior covered by the current implementation and tests; it does not imply support for every option of that association. The real-app matrix currently uses SQLite. PostgreSQL and MySQL have not been verified in a real-app run.

## Implemented features

| Priority | Active Record feature | Status | Implemented behavior |
|---|---|---|---|
| P1-01 | Rails 7.2 / 8.1 runtime compatibility | Supported | Three Ruby/Rails pairs run through the local real-app matrix. |
| P1-02 | Association macro detection | Supported | Reflections are classified; unsupported macros produce diagnostics. |
| P1-03 | Direct `has_many` / `has_one` | Supported | Direct associations and self joins have verified cardinalities. |
| P1-04 | `inverse_of` | Supported | Physical relationships are merged into a canonical edge independently of an inverse declaration. |
| P1-05 | `has_many :through` / `has_one :through` | Supported | Inferred-source one-step and nested paths are rendered as semantic edges without duplicate endpoints. |
| P1-06 | Polymorphic associations | Supported | Selected matching inverse candidates produce one normalized edge per concrete target. |
| P1-07 | `has_and_belongs_to_many` | Supported | A hidden join table is verified and rendered as one normalized many-to-many relationship. |

## Not yet supported

| Priority | Active Record feature | Needed for support |
|---|---|---|
| P2-01 | Scoped associations | Retain scope presence as metadata. |
| P2-02 | STI | Define how base and derived classes appear. |
| P2-03 | `delegated_type` | Render the delegator and concrete types. |
| P2-04 | Composite primary/foreign keys and `query_constraints` | Preserve and match key tuples. |
| P2-05 | Non-default `primary_key`, `source`, `source_type`, and `as` options | Resolve the target and key for each option. The supported polymorphic inverse case already uses `as:`. |
| P2-06 | Cross-domain and multi-database relationships | Represent external nodes or emit diagnostics. |
| P2-07 | `dependent`, `touch`, and `counter_cache` | Decide which behavior belongs in the diagram metadata. |
| P3-01 | `disable_joins`, `strict_loading`, and async | Decide whether execution properties belong in the diagram. |
| P3-02 | Association extensions | Represent or diagnose structural extensions. |

The supported baseline covers non-polymorphic, unscoped, scalar direct `belongs_to`; scalar `foreign_key` and `class_name`; conservative cardinalities from foreign keys, nullability, and unique indexes; same-domain ER/class output; diagnostics for excluded supported `belongs_to`; direct polymorphic `belongs_to` with selected `has_many` / `has_one ..., as:` inverse candidates; and unscoped scalar HABTM with a verified hidden join table.

## References

- [P0 contract](https://github.com/AudioStakes/rails-mmd/blob/main/docs/p0-contract.md)
- [Relationship builder](../lib/rails_mmd/relationship_builder.rb) and [render plan builder](../lib/rails_mmd/render_plan_builder.rb)
- [Rails Association Basics](https://guides.rubyonrails.org/association_basics.html), [Rails 7.2 API](https://api.rubyonrails.org/v7.2/classes/ActiveRecord/Associations/ClassMethods.html), [Rails 8.1 API](https://api.rubyonrails.org/v8.1/classes/ActiveRecord/Associations/ClassMethods.html)
