# frozen_string_literal: true

ActiveRecord::Schema[7.2].define(version: 20_260_719_000_006) do
  create_table 'p206_audits', force: :cascade do |t|
    t.integer 'account_id', null: false
  end
  create_table 'p206_archive_profiles', force: :cascade do |t|
    t.integer 'account_id', null: false
    t.index ['account_id'], name: 'index_p206_archive_profiles_on_account_id', unique: true
  end
  create_table 'p206_archive_notes', force: :cascade
  create_table 'p206_archive_documents', force: :cascade
  create_table 'p206_archive_assets', force: :cascade
  create_table 'p206_archive_articles', force: :cascade
  create_table 'p206_archive_only_articles', force: :cascade

  create_table 'p206_archive_authors', force: :cascade
  create_table 'p206_archive_tags', force: :cascade
  create_table 'p206_shared_links', id: false, force: :cascade do |t|
    t.integer 'author_id', null: false
    t.integer 'tag_id', null: false
  end
end
