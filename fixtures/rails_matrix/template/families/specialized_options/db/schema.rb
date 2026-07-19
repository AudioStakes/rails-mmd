# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength
ActiveRecord::Schema[7.2].define(version: 20_260_719_000_001) do
  create_table 'authors', force: :cascade do |t|
    t.string 'name', null: false
  end

  create_table 'tags', force: :cascade do |t|
    t.string 'name', null: false
  end

  create_table 'authors_tags', id: false, force: :cascade do |t|
    t.integer 'author_id', null: false
    t.integer 'tag_id', null: false
    t.index %w[author_id tag_id], name: 'index_authors_tags_unique', unique: true
  end

  create_table 'posts', force: :cascade do |t|
    t.string 'title', null: false
    t.integer 'author_id', null: false
    t.index ['author_id'], name: 'index_posts_on_author_id'
  end

  add_foreign_key 'posts', 'authors'

  create_table 'profiles', force: :cascade do |t|
    t.integer 'author_id', null: false
    t.index ['author_id'], name: 'index_profiles_on_author_id', unique: true
  end

  add_foreign_key 'profiles', 'authors'

  create_table 'drafts', force: :cascade do |t|
    t.integer 'author_id'
  end

  create_table 'notes', force: :cascade do |t|
    t.integer 'author_id', null: false
  end

  add_foreign_key 'notes', 'authors'

  create_table 'teams', force: :cascade do |t|
    t.string 'name', null: false
  end

  create_table 'memberships', force: :cascade do |t|
    t.integer 'author_id', null: false
    t.integer 'team_id', null: false
  end

  add_foreign_key 'memberships', 'authors'
  add_foreign_key 'memberships', 'teams'

  create_table 'partnerships', force: :cascade do |t|
    t.integer 'author_id', null: false
    t.integer 'collaborator_id', null: false
  end

  add_foreign_key 'partnerships', 'authors'
  add_foreign_key 'partnerships', 'teams', column: 'collaborator_id'

  create_table 'accounts', force: :cascade do |t|
    t.string 'name', null: false
  end

  create_table 'account_memberships', force: :cascade do |t|
    t.integer 'author_id', null: false
    t.integer 'account_id', null: false
    t.index ['author_id'], name: 'index_account_memberships_on_author_id', unique: true
    t.index ['account_id'], name: 'index_account_memberships_on_account_id', unique: true
  end

  add_foreign_key 'account_memberships', 'authors'
  add_foreign_key 'account_memberships', 'accounts'

  create_table 'labels', force: :cascade do |t|
    t.string 'name', null: false
  end

  create_table 'images', force: :cascade do |t|
    t.string 'name', null: false
  end

  create_table 'comments', force: :cascade do |t|
    t.integer 'commentable_id', null: false
    t.string 'commentable_type', null: false
    t.index %w[commentable_type commentable_id], name: 'index_comments_on_commentable'
  end

  create_table 'labelings', force: :cascade do |t|
    t.integer 'post_id', null: false
    t.integer 'label_id', null: false
  end

  add_foreign_key 'labelings', 'posts'
  add_foreign_key 'labelings', 'labels'

  create_table 'employees', force: :cascade do |t|
    t.integer 'manager_id'
  end

  create_table 'vehicles', force: :cascade do |t|
    t.string 'type'
    t.string 'name', null: false
  end

  create_table 'electric_vehicles', force: :cascade do |t|
    t.string 'type'
    t.string 'name', null: false
  end

  create_table 'messages', force: :cascade do |t|
    t.string 'kind'
    t.string 'subject', null: false
  end

  create_table 'animals', force: :cascade do |t|
    t.string 'type'
    t.string 'name', null: false
  end

  create_table 'devices', force: :cascade do |t|
    t.string 'type'
    t.string 'name', null: false
  end

  create_table 'appliances', force: :cascade do |t|
    t.string 'name', null: false
  end

  create_table 'spoilers', force: :cascade do |t|
    t.integer 'vehicle_id', null: false
    t.index ['vehicle_id'], name: 'index_spoilers_on_vehicle_id'
  end

  add_foreign_key 'spoilers', 'vehicles', column: 'vehicle_id'

  create_table 'p205_accounts', force: :cascade do |t|
    t.string 'account_code', null: false
    t.string 'region_code', null: false
    t.string 'local_code', null: false
    t.index ['account_code'], name: 'index_p205_accounts_on_account_code', unique: true
    t.index %w[region_code local_code], name: 'index_p205_accounts_on_region_and_local', unique: true
  end

  create_table 'p205_members', force: :cascade do |t|
    t.string 'owner_code', null: false
    t.string 'owner_region_code', null: false
    t.string 'owner_local_code', null: false
    t.index ['owner_code'], name: 'index_p205_members_on_owner_code'
    t.index %w[owner_region_code owner_local_code], name: 'index_p205_members_on_owner_tuple'
  end

  add_foreign_key 'p205_members', 'p205_accounts', column: 'owner_code', primary_key: 'account_code'
  add_foreign_key 'p205_members', 'p205_accounts',
                  column: %w[owner_region_code owner_local_code],
                  primary_key: %w[region_code local_code]

  create_table 'p205_profiles', force: :cascade do |t|
    t.string 'owner_code', null: false
    t.string 'owner_region_code', null: false
    t.string 'owner_local_code', null: false
    t.index ['owner_code'], name: 'index_p205_profiles_on_owner_code', unique: true
    t.index %w[owner_region_code owner_local_code], name: 'index_p205_profiles_on_owner_tuple', unique: true
  end

  add_foreign_key 'p205_profiles', 'p205_accounts', column: 'owner_code', primary_key: 'account_code'
  add_foreign_key 'p205_profiles', 'p205_accounts',
                  column: %w[owner_region_code owner_local_code],
                  primary_key: %w[region_code local_code]

  create_table 'p205_publications', force: :cascade
  create_table 'p205_writers', force: :cascade

  create_table 'p205_bylines', force: :cascade do |t|
    t.integer 'p205_publication_id', null: false
    t.integer 'p205_writer_id', null: false
  end

  add_foreign_key 'p205_bylines', 'p205_publications'
  add_foreign_key 'p205_bylines', 'p205_writers'

  create_table 'p205_collections', force: :cascade

  create_table 'p205_asset_links', force: :cascade do |t|
    t.integer 'p205_collection_id', null: false
    t.string 'resource_code', null: false
    t.string 'resource_kind', null: false
    t.index %w[resource_kind resource_code], name: 'index_p205_asset_links_on_resource'
  end

  add_foreign_key 'p205_asset_links', 'p205_collections'

  create_table 'p205_books', force: :cascade do |t|
    t.string 'catalog_code', null: false
    t.index ['catalog_code'], name: 'index_p205_books_on_catalog_code', unique: true
  end

  create_table 'p205_covers', force: :cascade do |t|
    t.string 'catalog_code', null: false
    t.index ['catalog_code'], name: 'index_p205_covers_on_catalog_code', unique: true
  end

  create_table 'p205_entries', force: :cascade do |t|
    t.string 'record_code', null: false
    t.string 'record_kind', null: false
    t.index %w[record_kind record_code], name: 'index_p205_entries_on_entryable', unique: true
  end

  create_table 'p205_articles', force: :cascade do |t|
    t.string 'slug', null: false
    t.index ['slug'], name: 'index_p205_articles_on_slug', unique: true
  end
end
# rubocop:enable Metrics/BlockLength
