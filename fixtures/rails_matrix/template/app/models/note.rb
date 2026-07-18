# frozen_string_literal: true

# Explicitly disables Rails inverse metadata while retaining one physical link.
class Note < ApplicationRecord
  belongs_to :author, inverse_of: false
  belongs_to :writer, class_name: 'Author', foreign_key: 'author_id', inverse_of: false
end
