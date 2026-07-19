# frozen_string_literal: true

require 'active_record'
require 'json'

# rubocop:disable Metrics/BlockLength, Style/Documentation, Style/OneClassPerFile
ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')

ActiveRecord::Schema.define do
  create_table :p205_accounts, force: true do |table|
    table.string :external_code, null: false
    table.string :tenant_code, null: false
    table.string :local_code, null: false
  end
  add_index :p205_accounts, :external_code, unique: true
  add_index :p205_accounts, %i[tenant_code local_code], unique: true

  create_table :p205_members, force: true do |table|
    table.string :account_code
    table.string :account_tenant_code
    table.string :account_local_code
  end

  create_table :p205_publications, force: true
  create_table :p205_authors, force: true do |table|
    table.string :pen_name
  end
  create_table :p205_authorships, force: true do |table|
    table.integer :publication_id
    table.integer :writer_id
  end

  create_table :p205_owners, force: true do |table|
    table.string :external_code, null: false
  end
  add_index :p205_owners, :external_code, unique: true

  create_table :p205_posts, force: true do |table|
    table.string :slug, null: false
  end
  add_index :p205_posts, :slug, unique: true

  create_table :p205_taggings, force: true do |table|
    table.integer :owner_id
    table.string :taggable_ref
    table.string :taggable_kind
  end

  create_table :p205_assets, force: true do |table|
    table.string :record_ref
    table.string :record_kind
  end

  create_table :p205_entries, force: true do |table|
    table.string :record_ref
    table.string :record_kind
  end
end

class P205Account < ActiveRecord::Base
  has_many :members_by_code,
           class_name: 'P205Member', foreign_key: :account_code, primary_key: :external_code,
           inverse_of: :account_by_code
  has_one :primary_member_by_code,
          class_name: 'P205Member', foreign_key: :account_code, primary_key: :external_code
  has_many :members_by_tuple,
           class_name: 'P205Member', foreign_key: %i[account_tenant_code account_local_code],
           primary_key: %i[tenant_code local_code], inverse_of: :account_by_tuple
  has_one :primary_member_by_tuple,
          class_name: 'P205Member', foreign_key: %i[account_tenant_code account_local_code],
          primary_key: %i[tenant_code local_code]
end

class P205Member < ActiveRecord::Base
  belongs_to :account_by_code,
             class_name: 'P205Account', foreign_key: :account_code, primary_key: :external_code,
             inverse_of: :members_by_code, optional: true
  belongs_to :account_by_tuple,
             class_name: 'P205Account', foreign_key: %i[account_tenant_code account_local_code],
             primary_key: %i[tenant_code local_code], inverse_of: :members_by_tuple, optional: true
end

class P205Publication < ActiveRecord::Base
  has_many :authorships, class_name: 'P205Authorship', foreign_key: :publication_id
  has_many :contributors, through: :authorships, source: :writer
end

class P205Author < ActiveRecord::Base
  has_many :authorships, class_name: 'P205Authorship', foreign_key: :writer_id
end

class P205Authorship < ActiveRecord::Base
  belongs_to :publication, class_name: 'P205Publication'
  belongs_to :writer, class_name: 'P205Author'
end

class P205Owner < ActiveRecord::Base
  has_many :taggings, class_name: 'P205Tagging', foreign_key: :owner_id
  has_many :articles, through: :taggings, source: :taggable, source_type: 'P205Post'
  has_many :documents,
           as: :record, class_name: 'P205Asset', foreign_key: :record_ref,
           foreign_type: :record_kind, primary_key: :external_code
  has_one :primary_document,
          as: :record, class_name: 'P205Asset', foreign_key: :record_ref,
          foreign_type: :record_kind, primary_key: :external_code
end

class P205Post < ActiveRecord::Base
  has_many :taggings,
           as: :taggable, class_name: 'P205Tagging', foreign_key: :taggable_ref, foreign_type: :taggable_kind,
           primary_key: :slug
end

class P205Tagging < ActiveRecord::Base
  belongs_to :owner, class_name: 'P205Owner'
  belongs_to :taggable,
             polymorphic: true, foreign_key: :taggable_ref, foreign_type: :taggable_kind,
             primary_key: :slug
end

class P205Asset < ActiveRecord::Base
  belongs_to :record,
             polymorphic: true, foreign_key: :record_ref, foreign_type: :record_kind,
             primary_key: :external_code
end

class P205Entry < ActiveRecord::Base
  delegated_type :record,
                 types: %w[P205Owner], foreign_key: :record_ref, foreign_type: :record_kind,
                 primary_key: :external_code
end

def tuple(value)
  Array(value).map(&:to_s)
end

def reflection(klass, name)
  klass.reflect_on_association(name)
end

account = P205Account.create!(external_code: 'acct-1', tenant_code: 'tenant-1', local_code: 'local-1')
member = P205Member.create!(
  account_code: 'acct-1', account_tenant_code: 'tenant-1', account_local_code: 'local-1'
)
publication = P205Publication.create!
author = P205Author.create!(pen_name: 'writer-1')
P205Authorship.create!(publication: publication, writer: author)
owner = P205Owner.create!(external_code: 'owner-1')
P205Post.create!(slug: 'post-1')
P205Tagging.create!(owner: owner, taggable_ref: 'post-1', taggable_kind: P205Post.polymorphic_name)
asset = P205Asset.create!(record_ref: 'owner-1', record_kind: P205Owner.polymorphic_name)
entry = P205Entry.create!(record_ref: 'owner-1', record_kind: P205Owner.polymorphic_name)

belongs_scalar = reflection(P205Member, :account_by_code)
has_scalar = reflection(P205Account, :members_by_code)
has_one_scalar = reflection(P205Account, :primary_member_by_code)
belongs_composite = reflection(P205Member, :account_by_tuple)
has_composite = reflection(P205Account, :members_by_tuple)
has_one_composite = reflection(P205Account, :primary_member_by_tuple)
explicit_source = reflection(P205Publication, :contributors)
typed_source = reflection(P205Owner, :articles)
polymorphic_root = reflection(P205Asset, :record)
polymorphic_inverse = reflection(P205Owner, :documents)
polymorphic_has_one_inverse = reflection(P205Owner, :primary_document)
delegated_root = reflection(P205Entry, :record)

payload = {
  rails_version: ActiveRecord.version.to_s,
  direct_primary_key: {
    belongs_to: {
      foreign_key: tuple(belongs_scalar.foreign_key),
      referenced_key: tuple(belongs_scalar.association_primary_key(P205Account)),
      loaded: member.account_by_code == account
    },
    has_many: {
      foreign_key: tuple(has_scalar.foreign_key),
      referenced_key: tuple(has_scalar.active_record_primary_key),
      loaded_ids: account.members_by_code.ids
    },
    has_one: {
      foreign_key: tuple(has_one_scalar.foreign_key),
      referenced_key: tuple(has_one_scalar.active_record_primary_key),
      loaded_id: account.primary_member_by_code.id
    },
    composite_belongs_to: {
      foreign_key: tuple(belongs_composite.foreign_key),
      referenced_key: tuple(belongs_composite.association_primary_key(P205Account)),
      loaded: member.account_by_tuple == account
    },
    composite_has_many: {
      foreign_key: tuple(has_composite.foreign_key),
      referenced_key: tuple(has_composite.active_record_primary_key),
      loaded_ids: account.members_by_tuple.ids
    },
    composite_has_one: {
      foreign_key: tuple(has_one_composite.foreign_key),
      referenced_key: tuple(has_one_composite.active_record_primary_key),
      loaded_id: account.primary_member_by_tuple.id
    }
  },
  explicit_source: {
    source_name: explicit_source.source_reflection.name.to_s,
    target_class: explicit_source.klass.name,
    chain: explicit_source.collect_join_chain.map { |entry| entry.name.to_s },
    loaded_ids: publication.contributors.ids
  },
  source_type: {
    source_name: typed_source.source_reflection.name.to_s,
    source_polymorphic: typed_source.source_reflection.polymorphic?,
    source_type: typed_source.options[:source_type],
    target_class: typed_source.klass.name,
    foreign_key: tuple(typed_source.foreign_key),
    foreign_type: typed_source.foreign_type.to_s,
    referenced_key: tuple(typed_source.association_primary_key(P205Post)),
    chain: typed_source.collect_join_chain.map { |entry| entry.name.to_s },
    loaded_ids: owner.articles.ids
  },
  specialized_as: {
    interface: polymorphic_inverse.options[:as].to_s,
    root_foreign_key: tuple(polymorphic_root.foreign_key),
    root_foreign_type: polymorphic_root.foreign_type.to_s,
    root_referenced_key: tuple(polymorphic_root.association_primary_key(P205Owner)),
    inverse_foreign_key: tuple(polymorphic_inverse.foreign_key),
    inverse_foreign_type: polymorphic_inverse.type.to_s,
    inverse_referenced_key: tuple(polymorphic_inverse.active_record_primary_key),
    loaded_root: asset.record == owner,
    loaded_inverse_ids: owner.documents.ids,
    has_one_foreign_key: tuple(polymorphic_has_one_inverse.foreign_key),
    has_one_foreign_type: polymorphic_has_one_inverse.type.to_s,
    has_one_referenced_key: tuple(polymorphic_has_one_inverse.active_record_primary_key),
    loaded_has_one_id: owner.primary_document.id
  },
  delegated_type: {
    types: P205Entry.record_types,
    root_foreign_key: tuple(delegated_root.foreign_key),
    root_foreign_type: delegated_root.foreign_type.to_s,
    root_referenced_key: tuple(delegated_root.association_primary_key(P205Owner)),
    loaded_root: entry.record == owner
  }
}

puts JSON.pretty_generate(payload)
# rubocop:enable Metrics/BlockLength, Style/Documentation, Style/OneClassPerFile
