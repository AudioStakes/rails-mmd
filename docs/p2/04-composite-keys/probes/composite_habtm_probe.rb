# frozen_string_literal: true

require 'active_record'
require 'json'

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')

ActiveRecord::Schema.define do
  create_table :p204_books, id: false, primary_key: %i[shop_id book_id], force: true do |table|
    table.integer :shop_id, null: false
    table.integer :book_id, null: false
  end

  create_table :p204_authors, id: false, primary_key: %i[first_name last_name], force: true do |table|
    table.string :first_name, null: false
    table.string :last_name, null: false
  end

  create_table :p204_authors_books, id: false, force: true do |table|
    table.integer :book_shop_id, null: false
    table.integer :book_book_id, null: false
    table.string :author_first_name, null: false
    table.string :author_last_name, null: false
  end
end

Object.const_set(:P204Book, Class.new(ActiveRecord::Base))
Object.const_set(:P204Author, Class.new(ActiveRecord::Base))

P204Book.table_name = 'p204_books'
P204Book.primary_key = %i[shop_id book_id]
P204Author.table_name = 'p204_authors'
P204Author.primary_key = %i[first_name last_name]

P204Book.has_and_belongs_to_many :authors,
                                 class_name: 'P204Author',
                                 join_table: :p204_authors_books,
                                 foreign_key: %i[book_shop_id book_book_id],
                                 association_foreign_key: %i[author_first_name author_last_name]

P204Author.has_and_belongs_to_many :books,
                                   class_name: 'P204Book',
                                   join_table: :p204_authors_books,
                                   foreign_key: %i[author_first_name author_last_name],
                                   association_foreign_key: %i[book_shop_id book_book_id]

def reflection_payload(model, association_name)
  reflection = model.reflect_on_association(association_name)

  {
    'foreign_key' => reflection.foreign_key,
    'association_foreign_key' => reflection.association_foreign_key,
    'active_record_primary_key' => reflection.active_record_primary_key,
    'association_primary_key' => reflection.association_primary_key,
    'join_primary_key' => reflection.join_primary_key,
    'join_foreign_key' => reflection.join_foreign_key
  }
end

book_sql = P204Book.new(shop_id: 1, book_id: 2).authors.to_sql
author_sql = P204Author.new(first_name: 'A', last_name: 'B').books.to_sql
book_where = book_sql.split(' WHERE ', 2).last
author_where = author_sql.split(' WHERE ', 2).last

puts JSON.pretty_generate(
  'rails_version' => ActiveRecord.version.to_s,
  'book_reflection' => reflection_payload(P204Book, :authors),
  'author_reflection' => reflection_payload(P204Author, :books),
  'book_sql' => book_sql,
  'author_sql' => author_sql,
  'book_sql_has_full_owner_tuple' =>
    %w[book_shop_id book_book_id].all? { |column| book_where.include?(column) },
  'book_sql_uses_scalar_fallback' => book_where.include?('p204_book_id'),
  'author_sql_has_full_owner_tuple' =>
    %w[author_first_name author_last_name].all? { |column| author_where.include?(column) },
  'author_sql_uses_scalar_fallback' => author_where.include?('p204_author_id')
)
