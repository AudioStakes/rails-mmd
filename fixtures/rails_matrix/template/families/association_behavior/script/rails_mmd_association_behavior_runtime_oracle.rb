# frozen_string_literal: true

require 'active_record'
require 'fileutils'
require 'json'

def normalize_value(value)
  value.is_a?(Symbol) ? value.to_s : value
end

def normalize_option(value)
  return normalize_value(value) unless value.is_a?(Hash)

  value.to_h { |key, nested_value| [key.to_s, normalize_value(nested_value)] }
end

def normalized_options(reflection)
  reflection.options.slice(:dependent, :touch, :counter_cache).to_h do |key, value|
    [key.to_s, normalize_option(value)]
  end
end

def reflection_payload(model, association_name)
  reflection = model.reflect_on_association(association_name)
  {
    'macro' => reflection.macro.to_s,
    'class_name' => reflection.class_name,
    'name' => reflection.name.to_s,
    'polymorphic' => reflection.polymorphic? == true,
    'options' => normalized_options(reflection)
  }
end

payload = {
  'direct' => {
    'belongs_to' => reflection_payload(P207Member, :account),
    'belongs_to_inactive_custom_counter' => reflection_payload(P207Member, :custom_account),
    'has_many' => reflection_payload(P207Account, :members),
    'has_one' => reflection_payload(P207Account, :profile),
    'has_many_restrict' => reflection_payload(P207Member, :notes)
  },
  'through' => {
    'has_many' => reflection_payload(P207Account, :notes),
    'has_one' => reflection_payload(P207Account, :latest_note)
  },
  'polymorphic' => {
    'root' => reflection_payload(P207Attachment, :attachable),
    'inverse' => reflection_payload(P207Article, :attachments)
  },
  'delegated_type' => {
    'root' => reflection_payload(P207Entry, :entryable),
    'inverse' => reflection_payload(P207Message, :entry)
  },
  'inverse_counter_naming_only' => {
    'has_many' => reflection_payload(P207InverseCounterAccount, :members),
    'belongs_to' => reflection_payload(P207InverseCounterMember, :account)
  },
  'habtm' => {
    'tags' => reflection_payload(P207Author, :tags)
  }
}

FileUtils.mkdir_p(Rails.root.join('tmp/rails_mmd'))
File.write(Rails.root.join('tmp/rails_mmd/association_behavior_runtime.json'), "#{JSON.pretty_generate(payload)}\n")
