# frozen_string_literal: true

# Same-leaf namespaced-pair delegated-type holder.
class DelegatedTypeSameLeafNamespaceHolder < ApplicationRecord
  delegated_type :same_leaf_reference,
                 types: [
                   'DelegatedTypeNamespaceA::SameLeafTarget',
                   'DelegatedTypeNamespaceB::SameLeafTarget',
                   'DelegatedTypeStiBase',
                   'DelegatedTypeStiLeaf',
                   'DelegatedTypeExcludedTarget',
                   'DelegatedTypeSecondDomainTarget'
                 ]
end
