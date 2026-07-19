# frozen_string_literal: true

module DelegatedTypeNamespaceB
  # Alternate namespaced leaf target for same-leaf delegated-type pairing.
  class SameLeafTarget < ApplicationRecord
    self.table_name = 'delegated_type_namespaced_b_same_leaf_targets'

    # inverse intentionally omitted
  end
end
