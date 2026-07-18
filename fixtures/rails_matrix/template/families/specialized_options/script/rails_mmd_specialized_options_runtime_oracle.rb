# frozen_string_literal: true

require 'fileutils'
require 'json'

def tuple(value)
  Array(value).map(&:to_s)
end

def reflection(model, name)
  model.reflect_on_association(name)
end

account = P205Account.create!(account_code: 'acct-1', region_code: 'north', local_code: 'one')
member = P205Member.create!(
  owner_code: 'acct-1', owner_region_code: 'north', owner_local_code: 'one'
)
P205Profile.create!(
  owner_code: 'acct-1', owner_region_code: 'north', owner_local_code: 'one'
)
publication = P205Publication.create!
writer = P205Writer.create!
P205Byline.create!(p205_publication: publication, credited_writer: writer)
collection = P205Collection.create!
book = P205Book.create!(catalog_code: 'book-1')
cover = P205Cover.create!(catalog_code: 'cover-1')
book_link = P205AssetLink.create!(
  p205_collection: collection, resource_code: 'book-1', resource_kind: P205Book.polymorphic_name
)
cover_link = P205AssetLink.create!(
  p205_collection: collection, resource_code: 'cover-1', resource_kind: P205Cover.polymorphic_name
)
article = P205Article.create!(slug: 'article-1')
entry = P205Entry.create!(record_code: 'article-1', record_kind: P205Article.polymorphic_name)

belongs_scalar = reflection(P205Member, :p205_account)
has_many_scalar = reflection(P205Account, :p205_members)
has_one_scalar = reflection(P205Account, :p205_profile)
belongs_composite = reflection(P205Member, :tuple_account)
has_many_composite = reflection(P205Account, :tuple_members)
has_one_composite = reflection(P205Account, :tuple_profile)
explicit_source = reflection(P205Publication, :contributors)
typed_source = reflection(P205Collection, :p205_books)
polymorphic_root = reflection(P205AssetLink, :resource)
polymorphic_many_inverse = reflection(P205Book, :p205_asset_links)
polymorphic_one_inverse = reflection(P205Cover, :p205_asset_link)
delegated_root = reflection(P205Entry, :entryable)
delegated_types_method = P205Entry.method(:entryable_types)
delegated_runtime_source = ActiveRecord::DelegatedType.instance_method(:delegated_type).source_location&.first
delegated_source = delegated_types_method.source_location&.first
delegated_source_suffix = delegated_source&.match(%r{activerecord-[^/]+/(lib/active_record/delegated_type\.rb)\z})

payload = {
  'direct_primary_key' => {
    'belongs_to' => {
      'foreign_key' => tuple(belongs_scalar.foreign_key),
      'referenced_key' => tuple(belongs_scalar.association_primary_key(P205Account)),
      'loaded' => member.p205_account == account
    },
    'has_many' => {
      'foreign_key' => tuple(has_many_scalar.foreign_key),
      'referenced_key' => tuple(has_many_scalar.active_record_primary_key),
      'loaded_ids' => account.p205_members.ids
    },
    'has_one' => {
      'foreign_key' => tuple(has_one_scalar.foreign_key),
      'referenced_key' => tuple(has_one_scalar.active_record_primary_key),
      'loaded_id' => account.p205_profile.id
    },
    'composite_belongs_to' => {
      'foreign_key' => tuple(belongs_composite.foreign_key),
      'referenced_key' => tuple(belongs_composite.association_primary_key(P205Account)),
      'loaded' => member.tuple_account == account
    },
    'composite_has_many' => {
      'foreign_key' => tuple(has_many_composite.foreign_key),
      'referenced_key' => tuple(has_many_composite.active_record_primary_key),
      'loaded_ids' => account.tuple_members.ids
    },
    'composite_has_one' => {
      'foreign_key' => tuple(has_one_composite.foreign_key),
      'referenced_key' => tuple(has_one_composite.active_record_primary_key),
      'loaded_id' => account.tuple_profile.id
    }
  },
  'explicit_source' => {
    'source_name' => explicit_source.source_reflection.name.to_s,
    'target_class' => explicit_source.klass.name,
    'chain' => explicit_source.collect_join_chain.map { |item| item.name.to_s },
    'loaded_ids' => publication.contributors.ids
  },
  'source_type' => {
    'source_name' => typed_source.source_reflection.name.to_s,
    'source_polymorphic' => typed_source.source_reflection.polymorphic?,
    'source_type' => typed_source.options[:source_type],
    'target_class' => typed_source.klass.name,
    'foreign_key' => tuple(typed_source.foreign_key),
    'foreign_type' => typed_source.foreign_type.to_s,
    'referenced_key' => tuple(typed_source.association_primary_key(P205Book)),
    'chain' => typed_source.collect_join_chain.map { |item| item.name.to_s },
    'loaded_ids' => collection.p205_books.ids
  },
  'specialized_as' => {
    'root_foreign_key' => tuple(polymorphic_root.foreign_key),
    'root_foreign_type' => polymorphic_root.foreign_type.to_s,
    'root_referenced_key' => tuple(polymorphic_root.association_primary_key(P205Book)),
    'many_interface' => polymorphic_many_inverse.options[:as].to_s,
    'many_foreign_key' => tuple(polymorphic_many_inverse.foreign_key),
    'many_foreign_type' => polymorphic_many_inverse.type.to_s,
    'many_referenced_key' => tuple(polymorphic_many_inverse.active_record_primary_key),
    'loaded_many_root' => book_link.resource == book,
    'loaded_many_inverse_ids' => book.p205_asset_links.ids,
    'one_interface' => polymorphic_one_inverse.options[:as].to_s,
    'one_foreign_key' => tuple(polymorphic_one_inverse.foreign_key),
    'one_foreign_type' => polymorphic_one_inverse.type.to_s,
    'one_referenced_key' => tuple(polymorphic_one_inverse.active_record_primary_key),
    'loaded_one_root' => cover_link.resource == cover,
    'loaded_one_inverse_id' => cover.p205_asset_link.id
  },
  'delegated_type' => {
    'types' => P205Entry.entryable_types,
    'root_foreign_key' => tuple(delegated_root.foreign_key),
    'root_foreign_type' => delegated_root.foreign_type.to_s,
    'root_referenced_key' => tuple(delegated_root.association_primary_key(P205Article)),
    'loaded_root' => entry.entryable == article,
    'generated_source_matches_runtime_delegated_type_source' => delegated_source == delegated_runtime_source,
    'generated_source_suffix' => delegated_source_suffix && "activerecord/#{delegated_source_suffix[1]}"
  }
}

output_root = Rails.root.join('tmp/rails_mmd')
FileUtils.mkdir_p(output_root)
File.write(output_root.join('specialized_options_runtime.json'), "#{JSON.pretty_generate(payload)}\n")
