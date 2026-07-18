# frozen_string_literal: true

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

  create_table 'employees', force: :cascade do |t|
    t.integer 'manager_id'
  end
end
