# frozen_string_literal: true

module DelegatedTypeNamespaceA
  # Namespaced leaf target for same-leaf delegated-type pairing.
  class SameLeafTarget < ApplicationRecord
    self.table_name = 'delegated_type_namespaced_a_same_leaf_targets'

    has_many :delegated_type_same_leaf_namespace_holders,
             -> { raise 'delegated inverse scope must not execute' },
             as: :same_leaf_reference,
             class_name: 'DelegatedTypeSameLeafNamespaceHolder'
  end
end
