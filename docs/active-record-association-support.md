# Active Record association support

The verified Rails series are 7.2 and 8.1. Support means the behavior below is
covered by the current implementation and tests; it does not cover every option
of an association. The real-app matrix uses SQLite. PostgreSQL and MySQL have
not been verified in a real-app run. See the [README](../README.md#compatibility-and-limits)
for the exact Ruby/Rails pairs.

## Supported relationships

All endpoints must be selected, renderable base models in the same configured
domain. Associations must be unscoped and use eligible scalar keys.

| Association | Behavior and limits |
|---|---|
| Direct `belongs_to` | Renders an existing scalar FK referencing the target's actual primary key. |
| Direct `has_many` / `has_one` | Renders the FK on the associated target. Includes self joins. `has_one` contributes a singular bound even without a unique DB index. |
| Reciprocal declarations and `inverse_of` | Merges the same physical relationship into one edge, independently of explicit, inferred, absent, or disabled inverse metadata. |
| `has_many :through` / `has_one :through` | Renders inferred-source one-step and nested paths as semantic edges alongside direct physical edges. Every intermediate model must also be selected. Explicit `source:` and `source_type:` are unsupported. |
| Polymorphic `belongs_to` | Renders one edge per concrete target found through selected matching direct `has_many` / `has_one ..., as:` inverses. Requires the default `<interface>_id` and `<interface>_type` columns. Both appear as FK attributes. |
| `has_and_belongs_to_many` | Verifies an id-less hidden join table containing exactly two distinct join columns and emits one many-to-many edge. Supports one-sided, reciprocal, alias, custom table/column, and self associations; payload/timestamp columns are unsupported. |

Scalar `foreign_key` and `class_name` options are supported for direct
relationships. A `primary_key` option is eligible only when it resolves to the
referenced entity's actual scalar primary key. HABTM applies the same actual-key
check to both endpoints; custom join-column names do not permit non-primary
endpoint keys.

Cardinality uses FK/nullability/unique-index evidence conservatively. Missing
optional DB metadata weakens that evidence and emits a diagnostic. Reflection
enumeration order does not change canonical IDs, labels, or edge counts.

## Unsupported or unrepresented behavior

| Feature | Current behavior |
|---|---|
| Association scopes | Omits scoped relationships with a warning; does not execute scope procs. A target model's `default_scope` alone is not an explicit direct-association scope. |
| STI subclasses | Cannot be selected as renderable entities; selecting one produces a domain error. |
| `delegated_type` specialization | Does not discover declared types or render a delegated-type hierarchy. Ordinary eligible underlying reflections follow the rules above. |
| Composite primary/foreign keys and `query_constraints` | Does not support key tuples; selected composite primary keys block the domain and composite association keys are omitted. |
| Non-primary association keys | Omits relationships that reference another column instead of the actual primary key. |
| Polymorphic through paths, custom polymorphic keys, and explicit through sources | Omits these declarations with diagnostics. The supported inverse polymorphic case uses `as:` as described above. |
| Cross-domain relationships | Does not create external nodes or auto-include targets. Out-of-domain targets on resolved association paths are diagnosed and omitted; polymorphic candidate discovery stays within the selected domain. |
| Multiple connection contexts in one domain | Blocks that domain with `MULTI_DB_UNSUPPORTED`. Separate domains are checked independently. |
| `dependent`, `touch`, `counter_cache`, `disable_joins`, `strict_loading`, async, and association extensions | Does not represent their behavioral metadata or guarantee execution semantics in the diagram. |

Inspect diagnostics whenever an expected edge is absent. Warning omissions
normally return exit `0`; use `--fail-on-warning` when they should fail a check.
These limits describe the current release, not a delivery roadmap.

## References

- [Generation contract](https://github.com/AudioStakes/rails-mmd/blob/main/docs/contract.md)
- [Relationship builder](../lib/rails_mmd/relationship_builder.rb) and [render plan builder](../lib/rails_mmd/render_plan_builder.rb)
- [Rails Association Basics](https://guides.rubyonrails.org/association_basics.html), [Rails 7.2 API](https://api.rubyonrails.org/v7.2/classes/ActiveRecord/Associations/ClassMethods.html), [Rails 8.1 API](https://api.rubyonrails.org/v8.1/classes/ActiveRecord/Associations/ClassMethods.html)
