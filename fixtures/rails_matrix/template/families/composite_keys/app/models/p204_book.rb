# frozen_string_literal: true

# Composite HABTM negative-oracle target fixture.
class P204Book < ApplicationRecord
  self.primary_key = %i[shop_id book_id]

  has_and_belongs_to_many :p204_authors,
                          class_name: 'P204Author',
                          join_table: 'p204_authors_books',
                          foreign_key: %i[book_shop_id book_book_id],
                          association_foreign_key: %i[author_first_name author_last_name]
end
