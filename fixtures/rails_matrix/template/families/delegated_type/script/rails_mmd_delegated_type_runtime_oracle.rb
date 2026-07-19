# frozen_string_literal: true

require 'fileutils'
require 'json'

holder = DelegatedTypeSameLeafNamespaceHolder
association_name = 'same_leaf_reference'
reflection = holder.reflect_on_association(association_name.to_sym)
generated_method = holder.method("#{association_name}_types")
generated_source_file = generated_method.source_location&.first
runtime_source_file = ActiveRecord::DelegatedType.instance_method(:delegated_type).source_location&.first
source_suffix = generated_source_file&.match(%r{activerecord-[^/]+/(lib/active_record/delegated_type\.rb)\z})

projection = [
  {
    'ruby_constant' => holder.name,
    'association_name' => association_name,
    'macro' => reflection.macro.to_s,
    'polymorphic' => reflection.polymorphic?,
    'foreign_key' => reflection.foreign_key.to_s,
    'foreign_type' => reflection.foreign_type.to_s,
    'types' => generated_method.call,
    'generated_source_matches_runtime_delegated_type_source' => generated_source_file == runtime_source_file,
    'generated_source_suffix' => source_suffix && "activerecord/#{source_suffix[1]}"
  }
]

output_root = Rails.root.join('tmp/rails_mmd')
FileUtils.mkdir_p(output_root)
File.write(output_root.join('delegated_type_runtime.json'), "#{JSON.pretty_generate(projection)}\n")
