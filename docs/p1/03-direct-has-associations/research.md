# P1-03 Direct Has Associations Research

Status: research complete; reviewed with no remaining findings

## Target

Render direct `has_many` and direct `has_one` associations on Rails 7.2 / 8.1.
P1-03 owns direct associations only. Canonical edge merging stays in P1-04.
`through`, scoped associations, polymorphic inverse (`as:`), and associations
that reference a non-primary owner column remain outside this feature unless an
existing omission code already covers them.

## Rails facts

- Rails 7.2.3.1 and 8.1.3 expose direct `has_many` as
  `ActiveRecord::Reflection::HasManyReflection` and direct `has_one` as
  `ActiveRecord::Reflection::HasOneReflection`.
- `collection?` is the stable discriminator for direct has-associations:
  `has_many` is `true`, `has_one` is `false`.
- Direct `has_many` / `has_one` report `through_reflection? == false`.
  Through variants must be excluded before direct key handling.
- `foreign_key` on direct `has_many` / `has_one` points to the target-table FK
  column, not the owner-table column.
- `active_record_primary_key` on direct `has_many` / `has_one` is the owner-side
  key used by the association. With `primary_key: "uuid"`, Rails 7.2.3.1 and
  8.1.3 report `active_record_primary_key == "uuid"` while
  `association_primary_key == "id"` on the direct `has_many` reflection.
- Self join uses the same reflection classes and methods. A self-referential
  `has_many :reports, class_name: "Employee", foreign_key: "manager_id"` is
  still a normal `HasManyReflection`.
- `inverse_of` can resolve for simple direct pairs, but automatic inverse
  detection is not a safe dependency for P1-03. Through, scoped, explicit
  `foreign_key`, and `inverse_of: false` cases can change or disable it.
- Reading `foreign_key` on a direct has-association can raise when Rails derives
  it through an unresolved inverse/class combination. Omission-only cases must
  not become fatal.

Reproduce the local probe against the locked matrix bundles:

```sh
for series in 7.2 8.1; do
  BUNDLE_GEMFILE="$PWD/fixtures/rails_matrix/bundles/$series/Gemfile" \
  BUNDLE_PATH="$PWD/.bundle/rails-matrix/gems/4.0.6" \
  ASDF_RUBY_VERSION=4.0.6 \
  asdf exec bundle exec ruby -e '
    require "active_record"
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
    ActiveRecord::Schema.define do
      create_table(:authors, force: true) { |t| t.string :uuid }
      add_index :authors, :uuid, unique: true
      create_table(:posts, force: true) { |t| t.integer :author_id; t.string :author_uuid }
      create_table(:profiles, force: true) { |t| t.integer :author_id }
      add_index :profiles, :author_id, unique: true
      create_table(:employees, force: true) { |t| t.integer :manager_id }
    end
    class Author < ActiveRecord::Base
      has_many :posts
      has_one :profile
    end
    class Post < ActiveRecord::Base
      belongs_to :author, optional: true
    end
    class Profile < ActiveRecord::Base
      belongs_to :author, optional: true
    end
    class Employee < ActiveRecord::Base
      belongs_to :manager, class_name: "Employee", optional: true, inverse_of: :reports
      has_many :reports, class_name: "Employee", foreign_key: "manager_id", inverse_of: :manager
    end
    class UuidAuthor < ActiveRecord::Base
      self.table_name = "authors"
      self.primary_key = "uuid"
      has_many :uuid_posts, class_name: "UuidPost", foreign_key: "author_uuid", primary_key: "uuid"
    end
    class UuidPost < ActiveRecord::Base
      self.table_name = "posts"
      belongs_to :uuid_author, class_name: "UuidAuthor", foreign_key: "author_uuid", primary_key: "uuid", optional: true
    end
    refs = {
      posts: Author.reflect_on_association(:posts),
      profile: Author.reflect_on_association(:profile),
      reports: Employee.reflect_on_association(:reports),
      uuid_posts: UuidAuthor.reflect_on_association(:uuid_posts)
    }
    puts "RAILS=#{ActiveRecord.version}"
    refs.each do |name, ref|
      puts [name, ref.class.name, ref.macro, ref.collection?,
            ref.through_reflection?, ref.foreign_key.inspect,
            ref.association_primary_key.inspect,
            ref.active_record_primary_key.inspect,
            ref.inverse_of&.name.inspect].join(" | ")
    end
  '
done
```

## Repository facts

- `RelationshipBuilder` currently renders only scalar `belongs_to`. Every other
  reflection becomes `ASSOCIATION_MACRO_OMITTED`.
- The current `Relationship` internal shape assumes the FK lives on the owner
  side: `owner_foreign_key_column`, `owner_fk_unique`, and
  `owner_fk_nullable`.
- `IrBuilder` marks foreign-key attributes only on
  `relationship.owner_entity_id` via `relationship.owner_foreign_key_column`.
- The public IR and render-plan schemas do not expose FK-side internals. They
  expose only entity IDs, relationship IDs, association names, and endpoint
  cardinalities.
- The real Rails matrix app already declares `Author.has_many :posts` and
  `Author.has_one :profile`, but P1-02 expects them to remain omission
  diagnostics. P1-03 must replace those expectations with rendered edges while
  keeping HABTM omitted.
- The matrix fixture has no `Profile` model or `profiles` table yet. Real
  `has_one` acceptance requires both plus a unique `profiles.author_id` index so
  application and database singularity agree.
- `relationship_id` is currently `relationships/<owner_table>/<association_name>`.
  Adding direct `has_many` / `has_one` before P1-04 will therefore create a
  second public edge for the same physical link when the inverse `belongs_to`
  already exists. For P1-03, an existing `belongs_to` wins over a
  physical-key-equivalent direct has candidate; P1-04 owns inverse-aware
  canonical labeling beyond this provisional deduplication.

## Contract tension

- The P0 contract says relationship eligibility is scalar `belongs_to` only.
  P1-03 must extend the contract, not merely the support matrix.
- The public diagnostic catalog may not need a new code. Direct `has_many` /
  `has_one` can likely reuse existing omission codes for unresolved target,
  out-of-domain target, composite key, missing key column, custom/non-primary
  key, unsafe name, and scoped association.
- `ASSOCIATION_MACRO_OMITTED` becomes a partial-macro fallback after P1-03. It
  should remain for unsupported `has_many` / `has_one` variants such as
  `through` until their owning feature lands.
- A custom `primary_key:` is eligible when it resolves to the declaring
  entity's actual scalar primary key. A different owner column remains omitted
  with `ASSOCIATION_NON_PRIMARY_KEY_OMITTED`.

## Risks and design inputs

- The highest-risk implementation bug is endpoint inversion. Reusing the current
  owner-side FK evidence unchanged would attach FK attributes to the wrong
  entity and derive wrong multiplicities.
- If P1-03 keeps the current internal relationship shape, direct `has_many` /
  `has_one` likely need normalization to the FK-holding side so `IrBuilder` can
  still attach FK attributes correctly without a public IR/schema change.
- Direct support should not depend on inverse discovery. P1-04 owns semantic
  inverse matching; P1-03 uses only the provisional physical-key winner above.
- Self join must be covered in P1-03 because it is still a direct has-many edge
  and is the fastest way to expose owner/target swaps.
- `has_one` renders the Active Record singular upper bound `0..1` even without
  target-FK uniqueness. The real matrix fixture supplies a unique index so its
  application and database semantics agree.
- Direct custom `primary_key:` is a real boundary. The local probe shows direct
  `has_many` uses `active_record_primary_key`, not `association_primary_key`, to
  expose the owner-side key. Reusing the `belongs_to` key path would be wrong.
- Any direct implementation that reads `foreign_key` before safe guardrails for
  `through`, target resolution, or inverse-derived failures risks turning a
  warning path into a fatal path.
- The self-join oracle uses direct `Employee.has_many :reports` with nullable
  `manager_id` and no inverse declaration: one self edge labeled `reports`,
  owner endpoint `0..1`, target endpoint `0..many`. A unit case proves an
  inverse `belongs_to :manager` wins the provisional duplicate.

## Research review record

| Round | Perspective | Findings | Correction |
|---|---|---|---|
| 1 | Rails runtime | `through_reflection?` must be excluded explicitly; `foreign_key` can raise during inverse-derived resolution; singular direct edges need an explicit multiplicity policy; FK-side normalization is the smallest internal fit | Recorded explicit through guard, key-reader failure boundary, duplicate-edge boundary, and the multiplicity/FK-normalization decisions that design must resolve |
| 1 | Architecture | Non-primary-key scope and missing real `Profile` fixture were unclear | Limited omission to non-primary owner columns and specified the fixture expansion |
| 1 | QA / contract | Custom owner key, non-unique `has_one`, and self-join outcomes were unresolved | Fixed the eligible key rule, singular macro bound, provisional dedupe, and self-join oracle |
| 2 | Rails runtime | None | — |
| 2 | Architecture | None | — |
| 2 | QA / contract | None | — |

## Sources

- [Rails guide: Association Basics](https://guides.rubyonrails.org/association_basics.html)
- [Rails 7.2 Reflection API](https://api.rubyonrails.org/v7.2.3.1/classes/ActiveRecord/Reflection/ClassMethods.html)
- [Rails 8.1 Reflection API](https://api.rubyonrails.org/v8.1.3/classes/ActiveRecord/Reflection/ClassMethods.html)
- [Rails 7.2 association API](https://api.rubyonrails.org/v7.2/classes/ActiveRecord/Associations/ClassMethods.html)
- [Rails 8.1 association API](https://api.rubyonrails.org/v8.1/classes/ActiveRecord/Associations/ClassMethods.html)
- `lib/rails_mmd/relationship_builder.rb`
- `lib/rails_mmd/ir_builder.rb`
- `schemas/ir.schema.json`
- `schemas/render_plan.schema.json`
- `tooling/rails_matrix.rb`
- `fixtures/rails_matrix/template/app/models/author.rb`
- `fixtures/rails_matrix/template/rails_mmd_expected_diagnostics.json`
- `docs/p0-contract.md`
- `docs/active-record-association-support.md`
