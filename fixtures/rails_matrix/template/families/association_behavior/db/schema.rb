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

  create_table 'p207_accounts', force: :cascade do |t|
    t.integer 'p207_members_count', default: 0, null: false
    t.integer 'custom_members_count', default: 0, null: false
    t.datetime 'members_touched_at'
    t.datetime 'profile_touched_at'
  end

  create_table 'p207_members', force: :cascade do |t|
    t.integer 'account_id', null: false
    t.integer 'custom_account_id'
    t.index ['account_id'], name: 'index_p207_members_on_account_id'
    t.index ['custom_account_id'], name: 'index_p207_members_on_custom_account_id'
  end

  create_table 'p207_profiles', force: :cascade do |t|
    t.integer 'account_id', null: false
    t.index ['account_id'], name: 'index_p207_profiles_on_account_id'
  end

  create_table 'p207_notes', force: :cascade do |t|
    t.integer 'member_id', null: false
    t.index ['member_id'], name: 'index_p207_notes_on_member_id'
  end

  create_table 'p207_attachments', force: :cascade do |t|
    t.integer 'attachable_id', null: false
    t.string 'attachable_type', null: false
    t.index %w[attachable_type attachable_id], name: 'index_p207_attachments_on_attachable'
  end

  create_table 'p207_articles', force: :cascade do |t|
    t.integer 'attachments_count', default: 0, null: false
  end

  create_table 'p207_entries', force: :cascade do |t|
    t.integer 'entryable_id', null: false
    t.string 'entryable_type', null: false
    t.index %w[entryable_type entryable_id], name: 'index_p207_entries_on_entryable'
  end

  create_table 'p207_messages', force: :cascade do |t|
    t.integer 'entries_count', default: 0, null: false
  end

  create_table 'p207_authors', force: :cascade
  create_table 'p207_tags', force: :cascade

  create_table 'p207_authors_tags', id: false, force: :cascade do |t|
    t.integer 'author_id', null: false
    t.integer 'tag_id', null: false
    t.index %w[author_id tag_id], name: 'index_p207_authors_tags_unique', unique: true
  end

  create_table 'p207_inverse_counter_accounts', force: :cascade
  create_table 'p207_inverse_counter_members', force: :cascade do |t|
    t.integer 'account_id', null: false
    t.index ['account_id'], name: 'index_p207_inverse_members_on_account_id'
  end

  add_foreign_key 'p207_members', 'p207_accounts', column: 'account_id'
  add_foreign_key 'p207_profiles', 'p207_accounts', column: 'account_id'
  add_foreign_key 'p207_notes', 'p207_members', column: 'member_id'
  add_foreign_key 'p207_inverse_counter_members', 'p207_inverse_counter_accounts', column: 'account_id'
end
# rubocop:enable Metrics/BlockLength
