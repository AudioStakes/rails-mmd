# frozen_string_literal: true

# Target with undeclared inverse coverage.
class DelegatedTypeUndeclaredInverseTarget < ApplicationRecord
  has_many :delegated_type_same_leaf_namespace_holders,
           as: :same_leaf_reference,
           class_name: 'DelegatedTypeSameLeafNamespaceHolder'
end
