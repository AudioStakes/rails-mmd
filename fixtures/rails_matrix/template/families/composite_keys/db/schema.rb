# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength
ActiveRecord::Schema[7.2].define(version: 20_260_718_000_001) do
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

  create_table 'p204_shops', id: false, primary_key: %i[region_code shop_code], force: :cascade do |t|
    t.string 'region_code', null: false
    t.integer 'shop_code', null: false
  end

  create_table 'p204_orders', id: false, primary_key: %i[shop_region_code order_code], force: :cascade do |t|
    t.string 'shop_region_code', null: false
    t.integer 'shop_code', null: false
    t.integer 'order_code', null: false
    t.index %w[shop_region_code shop_code], name: 'index_p204_orders_on_shop'
  end

  add_foreign_key 'p204_orders', 'p204_shops',
                  column: %w[shop_region_code shop_code],
                  primary_key: %w[region_code shop_code]

  create_table 'p204_line_items', id: false, primary_key: %i[shop_region_code order_code], force: :cascade do |t|
    t.string 'shop_region_code', null: false
    t.integer 'order_code', null: false
    t.string 'description', null: false
  end

  add_foreign_key 'p204_line_items', 'p204_orders',
                  column: %w[shop_region_code order_code],
                  primary_key: %w[shop_region_code order_code]

  create_table 'p204_warehouses', force: :cascade do |t|
    t.string 'region_code', null: false
    t.string 'name', null: false
  end

  create_table 'p204_bins', force: :cascade do |t|
    t.string 'region_code', null: false
    t.integer 'warehouse_id', null: false
  end

  create_table 'p204_warehouse_profiles', force: :cascade do |t|
    t.string 'region_code', null: false
    t.integer 'warehouse_id', null: false
    t.index %w[warehouse_id region_code], name: 'index_p204_warehouse_profiles_unique', unique: true
  end

  create_table 'p204_catalogs', force: :cascade do |t|
    t.string 'tenant_id', null: false
    t.string 'name', null: false
  end

  create_table 'p204_catalog_items', force: :cascade do |t|
    t.integer 'p204_catalog_id', null: false
  end

  create_table 'p204_attachments', force: :cascade do |t|
    t.string 'attachable_region_code', null: false
    t.integer 'attachable_id', null: false
    t.string 'attachable_type', null: false
  end

  create_table 'p204_entries', force: :cascade do |t|
    t.string 'entryable_region_code', null: false
    t.integer 'entryable_id', null: false
    t.string 'entryable_type', null: false
  end

  create_table 'p204_posts', id: false, primary_key: %i[region_code post_code], force: :cascade do |t|
    t.string 'region_code', null: false
    t.integer 'post_code', null: false
  end

  create_table 'p204_books', id: false, primary_key: %i[shop_id book_id], force: :cascade do |t|
    t.integer 'shop_id', null: false
    t.integer 'book_id', null: false
  end

  create_table 'p204_authors', id: false, primary_key: %i[first_name last_name], force: :cascade do |t|
    t.string 'first_name', null: false
    t.string 'last_name', null: false
  end

  create_table 'p204_authors_books', id: false, force: :cascade do |t|
    t.integer 'book_shop_id', null: false
    t.integer 'book_book_id', null: false
    t.string 'author_first_name', null: false
    t.string 'author_last_name', null: false
  end
end
# rubocop:enable Metrics/BlockLength
