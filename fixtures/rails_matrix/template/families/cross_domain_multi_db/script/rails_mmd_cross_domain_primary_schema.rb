# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength
ActiveRecord::Schema[7.2].define(version: 20_260_719_000_006) do
  create_table 'p206_accounts', force: :cascade

  create_table 'p206_orders', force: :cascade do |t|
    t.integer 'account_id', null: false
    t.index ['account_id'], name: 'index_p206_orders_on_account_id'
  end
  add_foreign_key 'p206_orders', 'p206_accounts', column: 'account_id'

  create_table 'p206_memberships', force: :cascade do |t|
    t.integer 'account_id', null: false
    t.integer 'archive_note_id', null: false
    t.index ['account_id'], name: 'index_p206_memberships_on_account_id'
  end
  add_foreign_key 'p206_memberships', 'p206_accounts', column: 'account_id'

  create_table 'p206_shared_targets', force: :cascade do |t|
    t.integer 'account_id', null: false
  end

  create_table 'p206_attachments', force: :cascade do |t|
    t.integer 'attachable_id', null: false
    t.string 'attachable_type', null: false
    t.index %w[attachable_type attachable_id], name: 'index_p206_attachments_on_attachable'
  end
  create_table 'p206_archive_only_attachments', force: :cascade do |t|
    t.integer 'archived_asset_id', null: false
    t.string 'archived_asset_type', null: false
    t.index %w[archived_asset_type archived_asset_id], name: 'index_p206_attachments_on_archived_asset'
  end

  create_table 'p206_local_documents', force: :cascade
  create_table 'p206_entries', force: :cascade do |t|
    t.integer 'entryable_id', null: false
    t.string 'entryable_type', null: false
  end
  create_table 'p206_local_articles', force: :cascade
  create_table 'p206_archive_only_entries', force: :cascade do |t|
    t.integer 'archive_subject_id', null: false
    t.string 'archive_subject_type', null: false
  end

  create_table 'p206_primary_authors', force: :cascade
  create_table 'p206_primary_tags', force: :cascade
  create_table 'p206_shared_links', id: false, force: :cascade do |t|
    t.integer 'author_id', null: false
    t.integer 'tag_id', null: false
  end
  create_table 'p206_cross_links', id: false, force: :cascade do |t|
    t.integer 'author_id', null: false
    t.integer 'tag_id', null: false
  end
end
# rubocop:enable Metrics/BlockLength
