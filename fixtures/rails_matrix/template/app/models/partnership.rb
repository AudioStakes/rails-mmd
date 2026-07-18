# frozen_string_literal: true

# Second inferred path to Team for through identity coverage.
class Partnership < ApplicationRecord
  belongs_to :author
  belongs_to :collaborator, class_name: 'Team'
end
