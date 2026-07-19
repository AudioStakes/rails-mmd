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

  create_table 'delegated_type_same_leaf_namespace_holders', force: :cascade do |t|
    t.integer 'same_leaf_reference_id', null: false
    t.string 'same_leaf_reference_type', null: false
  end

  create_table 'delegated_type_namespaced_a_same_leaf_targets', force: :cascade do |t|
    t.string 'name', null: false
  end

  create_table 'delegated_type_namespaced_b_same_leaf_targets', force: :cascade do |t|
    t.string 'name', null: false
  end

  create_table 'delegated_type_scoped_inverse_raising_holders', force: :cascade do |t|
    t.integer 'scoped_inverse_raising_reference_id', null: false
    t.string 'scoped_inverse_raising_reference_type', null: false
  end

  create_table 'delegated_type_scoped_inverse_raising_targets', force: :cascade do |t|
    t.string 'name', null: false
  end

  create_table 'delegated_type_no_inverse_holders', force: :cascade do |t|
    t.integer 'no_inverse_reference_id', null: false
    t.string 'no_inverse_reference_type', null: false
  end

  create_table 'delegated_type_no_inverse_targets', force: :cascade do |t|
    t.string 'name', null: false
  end

  create_table 'delegated_type_sti_holders', force: :cascade do |t|
    t.integer 'sti_recordable_id', null: false
    t.string 'sti_recordable_type', null: false
  end

  create_table 'delegated_type_sti_records', force: :cascade do |t|
    t.string 'type', null: false
    t.string 'name', null: false
  end

  create_table 'delegated_type_excluded_holders', force: :cascade do |t|
    t.integer 'excluded_reference_id', null: false
    t.string 'excluded_reference_type', null: false
  end

  create_table 'delegated_type_excluded_targets', force: :cascade do |t|
    t.string 'name', null: false
  end

  create_table 'delegated_type_second_domain_owners', force: :cascade do |t|
    t.integer 'cross_domain_reference_id', null: false
    t.string 'cross_domain_reference_type', null: false
  end

  create_table 'delegated_type_second_domain_targets', force: :cascade do |t|
    t.string 'name', null: false
  end

  create_table 'delegated_type_undeclared_inverse_holders', force: :cascade do |t|
    t.integer 'undeclared_inverse_reference_id', null: false
    t.string 'undeclared_inverse_reference_type', null: false
  end

  create_table 'delegated_type_undeclared_inverse_targets', force: :cascade do |t|
    t.string 'name', null: false
  end
end
# rubocop:enable Metrics/BlockLength
