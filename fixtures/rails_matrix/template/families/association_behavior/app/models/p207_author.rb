# frozen_string_literal: true

# HABTM unsupported-option echo fixture owner.
class P207Author < ApplicationRecord
  has_and_belongs_to_many :tags,
                          class_name: 'P207Tag', join_table: 'p207_authors_tags',
                          foreign_key: :author_id, association_foreign_key: :tag_id, dependent: :destroy,
                          touch: true, counter_cache: :authors_count
end
