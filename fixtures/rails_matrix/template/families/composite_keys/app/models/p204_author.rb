# frozen_string_literal: true

# Composite HABTM negative-oracle owner fixture.
class P204Author < ApplicationRecord
  self.primary_key = %i[first_name last_name]

  has_and_belongs_to_many :p204_books,
                          class_name: 'P204Book',
                          join_table: 'p204_authors_books',
                          foreign_key: %i[author_first_name author_last_name],
                          association_foreign_key: %i[book_shop_id book_book_id]
end
