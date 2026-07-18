# frozen_string_literal: true

# Direct custom referenced-key owner fixture.
class P205Account < ApplicationRecord
  has_many :p205_members,
           foreign_key: :owner_code,
           primary_key: :account_code,
           inverse_of: :p205_account
  has_one :p205_profile,
          foreign_key: :owner_code,
          primary_key: :account_code,
          inverse_of: :p205_account
  has_many :tuple_members,
           class_name: 'P205Member',
           foreign_key: %i[owner_region_code owner_local_code],
           primary_key: %i[region_code local_code],
           inverse_of: :tuple_account
  has_one :tuple_profile,
          class_name: 'P205Profile',
          foreign_key: %i[owner_region_code owner_local_code],
          primary_key: %i[region_code local_code],
          inverse_of: :tuple_account
end
