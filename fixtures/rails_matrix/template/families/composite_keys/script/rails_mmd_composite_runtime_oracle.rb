# frozen_string_literal: true

require 'fileutils'
require 'json'

ASSOCIATION_TARGETS = {
  P204Attachment => { attachable: [P204Order, P204Shop] },
  P204Author => { p204_books: P204Book },
  P204Bin => { p204_warehouse: P204Warehouse },
  P204Book => { p204_authors: P204Author },
  P204Catalog => { p204_catalog_items: P204CatalogItem },
  P204CatalogItem => { p204_catalog: P204Catalog },
  P204Entry => { entryable: P204Post },
  P204LineItem => { p204_order: P204Order },
  P204Order => {
    p204_shop: P204Shop,
    p204_line_items: P204LineItem,
    p204_attachments: P204Attachment
  },
  P204Post => { p204_entry: P204Entry },
  P204Shop => {
    p204_orders: P204Order,
    p204_line_items: P204LineItem,
    p204_attachments: P204Attachment
  },
  P204Warehouse => {
    p204_bins: P204Bin,
    p204_warehouse_profile: P204WarehouseProfile
  },
  P204WarehouseProfile => { p204_warehouse: P204Warehouse }
}.freeze

def normalized(value)
  return if value.nil?
  return value.map(&:to_s) if value.is_a?(Array)

  value.to_s
end

def reflection_value(reflection, reader, target = nil)
  value = if reader == :association_primary_key && reflection.polymorphic?
            reflection.public_send(reader, target)
          else
            reflection.public_send(reader)
          end
  normalized(value)
rescue StandardError => e
  { 'error' => e.class.name }
end

models = ASSOCIATION_TARGETS.keys.sort_by(&:name).map do |model|
  association_targets = ASSOCIATION_TARGETS.fetch(model).flat_map do |name, targets|
    Array(targets).map { |target| [name, target] }
  end
  associations = association_targets.sort_by { |name, target| [name.to_s, target.name] }.map do |name, target|
    reflection = model.reflect_on_association(name)
    payload = {
      'name' => name.to_s,
      'macro' => reflection.macro.to_s,
      'polymorphic' => reflection.polymorphic?,
      'foreign_key' => reflection_value(reflection, :foreign_key),
      'association_primary_key' => reflection_value(reflection, :association_primary_key, target),
      'active_record_primary_key' => reflection_value(reflection, :active_record_primary_key),
      'join_primary_key' => reflection_value(reflection, :join_primary_key),
      'join_foreign_key' => reflection_value(reflection, :join_foreign_key),
      'query_constraints' => normalized(reflection.options[:query_constraints])
    }
    payload['target_ruby_constant'] = target.name if reflection.polymorphic?
    payload
  end

  {
    'ruby_constant' => model.name,
    'primary_key' => normalized(model.primary_key),
    'query_constraints' => normalized(model.query_constraints_list),
    'associations' => associations
  }
end

output_root = Rails.root.join('tmp/rails_mmd')
FileUtils.mkdir_p(output_root)
File.write(output_root.join('composite_runtime.json'), "#{JSON.pretty_generate(models)}\n")
