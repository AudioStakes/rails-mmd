# frozen_string_literal: true

# Direct has-one custom referenced-key fixture.
class P205Profile < ApplicationRecord
  belongs_to :p205_account,
             foreign_key: :owner_code,
             primary_key: :account_code,
             inverse_of: :p205_profile
  belongs_to :tuple_account,
             class_name: 'P205Account',
             foreign_key: %i[owner_region_code owner_local_code],
             primary_key: %i[region_code local_code],
             inverse_of: :tuple_profile
end
