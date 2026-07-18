# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength
ActiveRecord::Schema[7.2].define(version: 20_260_718_000_001) do
  create_table 'authors', force: :cascade do |t|
    t.string 'name', null: false
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
end
# rubocop:enable Metrics/BlockLength
