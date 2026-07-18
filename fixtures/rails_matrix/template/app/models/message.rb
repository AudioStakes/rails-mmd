# frozen_string_literal: true

# STI base with a custom inheritance column.
class Message < ApplicationRecord
  self.inheritance_column = 'kind'
end
