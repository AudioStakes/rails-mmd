# frozen_string_literal: true

require 'active_record'
require 'json'

# rubocop:disable Metrics/MethodLength, Style/Documentation, Style/OneClassPerFile
class P207Account < ActiveRecord::Base
  has_many :members,
           class_name: 'P207Member', dependent: :destroy
  has_one :profile, class_name: 'P207Profile', dependent: :nullify, touch: :profile_touched_at
  has_many :notes, through: :members, source: :notes, dependent: :delete_all
  has_one :latest_note, through: :members, source: :notes,
                        dependent: :destroy, touch: :latest_note_touched_at
end

class P207Member < ActiveRecord::Base
  belongs_to :account,
             class_name: 'P207Account', dependent: :delete, touch: :members_touched_at,
             counter_cache: true
  belongs_to :custom_account,
             class_name: 'P207Account', counter_cache: { active: false, column: :custom_members_count },
             optional: true
  has_many :notes, class_name: 'P207Note', dependent: :restrict_with_error
end

class P207Profile < ActiveRecord::Base
  belongs_to :account, class_name: 'P207Account', optional: true
end

class P207Note < ActiveRecord::Base
  belongs_to :member, class_name: 'P207Member'
end

class P207Attachment < ActiveRecord::Base
  belongs_to :attachable,
             polymorphic: true, dependent: :destroy, touch: true,
             counter_cache: :attachments_count
end

class P207Article < ActiveRecord::Base
  has_many :attachments, as: :attachable, class_name: 'P207Attachment', dependent: :nullify
end

class P207Entry < ActiveRecord::Base
  delegated_type :entryable,
                 types: %w[P207Message], dependent: :destroy, touch: true,
                 counter_cache: :entries_count
end

class P207Message < ActiveRecord::Base
  has_one :entry, as: :entryable, class_name: 'P207Entry', dependent: :nullify
end

class P207Author < ActiveRecord::Base
  has_and_belongs_to_many :tags,
                          class_name: 'P207Tag', dependent: :destroy,
                          touch: true, counter_cache: :authors_count
end

class P207Tag < ActiveRecord::Base
end

class P207InverseCounterAccount < ActiveRecord::Base
  has_many :members,
           class_name: 'P207InverseCounterMember', foreign_key: :account_id,
           counter_cache: :inverse_named_members_count
end

class P207InverseCounterMember < ActiveRecord::Base
  belongs_to :account,
             class_name: 'P207InverseCounterAccount', foreign_key: :account_id
end

def json_value(value)
  case value
  when Hash
    value.to_h { |key, item| [key.to_s, json_value(item)] }
  when Array
    value.map { |item| json_value(item) }
  when Symbol
    value.to_s
  else
    value
  end
end

def behavior_projection(model, association_name)
  reflection = model.reflect_on_association(association_name)
  options = reflection.options.slice(:dependent, :touch, :counter_cache)
  projection = {
    'macro' => reflection.macro.to_s,
    'reflection_class' => reflection.class.name,
    'through' => reflection.through_reflection?.equal?(true),
    'options' => json_value(options),
    'proposed_public_declaration' => proposed_public_declaration(reflection, association_name, options)
  }
  add_counter_cache_evidence(projection, reflection) if options[:counter_cache]
  projection
end

def proposed_public_declaration(reflection, association_name, options)
  return if reflection.macro == :has_and_belongs_to_many

  behavior = {}
  add_dependent_behavior(behavior, reflection, options[:dependent])
  add_touch_behavior(behavior, reflection, options[:touch])
  add_counter_cache_behavior(behavior, reflection, options[:counter_cache])
  return if behavior.empty?

  { 'association_name' => association_name.to_s, 'association_macro' => reflection.macro.to_s }.merge(behavior)
end

def add_dependent_behavior(behavior, reflection, dependent)
  return unless dependent
  return if reflection.macro == :has_one && reflection.through_reflection?

  target = reflection.macro == :has_many && reflection.through_reflection? ? 'through_records' : 'associated_records'
  behavior['dependent'] = { 'action' => dependent.to_s, 'target' => target }
end

def add_touch_behavior(behavior, reflection, touch)
  return unless touch && %i[belongs_to has_one].include?(reflection.macro)

  behavior['touch'] = { 'attribute' => touch == true ? nil : touch.to_s }
end

def add_counter_cache_behavior(behavior, reflection, counter_cache)
  return unless counter_cache && reflection.macro == :belongs_to

  behavior['counter_cache'] = {
    'column' => reflection.counter_cache_column.to_s,
    'active' => counter_cache.fetch(:active)
  }
end

def add_counter_cache_evidence(projection, reflection)
  projection['counter_cache_column'] = reflection.counter_cache_column.to_s
  projection['has_cached_counter_value'] = json_value(reflection.has_cached_counter?)
  projection['has_cached_counter'] = !reflection.has_cached_counter?.nil?
  projection['has_active_cached_counter'] = !!reflection.has_active_cached_counter?
end

payload = {
  'rails_version' => ActiveRecord.version.to_s,
  'direct' => {
    'belongs_to' => behavior_projection(P207Member, :account),
    'belongs_to_inactive_custom_counter' => behavior_projection(P207Member, :custom_account),
    'has_many' => behavior_projection(P207Account, :members),
    'has_one' => behavior_projection(P207Account, :profile)
  },
  'through' => {
    'has_many' => behavior_projection(P207Account, :notes),
    'has_one' => behavior_projection(P207Account, :latest_note)
  },
  'polymorphic' => {
    'root' => behavior_projection(P207Attachment, :attachable),
    'inverse' => behavior_projection(P207Article, :attachments)
  },
  'delegated_type' => {
    'root' => behavior_projection(P207Entry, :entryable),
    'inverse' => behavior_projection(P207Message, :entry)
  },
  'inverse_counter_naming_only' => {
    'has_many' => behavior_projection(P207InverseCounterAccount, :members),
    'belongs_to' => behavior_projection(P207InverseCounterMember, :account)
  },
  'habtm' => behavior_projection(P207Author, :tags)
}

puts JSON.pretty_generate(payload)
# rubocop:enable Metrics/MethodLength, Style/Documentation, Style/OneClassPerFile
