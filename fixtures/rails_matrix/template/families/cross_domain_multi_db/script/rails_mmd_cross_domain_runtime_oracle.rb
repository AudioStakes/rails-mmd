# frozen_string_literal: true

require 'fileutils'
require 'json'

def reflection(owner, name)
  owner.reflect_on_association(name)
end

def same_context?(left, right)
  left.connection_db_config.name == right.connection_db_config.name &&
    left.current_role == right.current_role &&
    left.current_shard == right.current_shard
end

direct = {
  'belongs_to' => reflection(P206::Audit, :account),
  'has_many' => reflection(P206::Account, :audits),
  'has_one' => reflection(P206::Account, :archive_profile)
}
through = reflection(P206::Account, :archive_notes)
polymorphic_root = reflection(P206::Attachment, :attachable)
polymorphic_all_rejected_root = reflection(P206::ArchiveOnlyAttachment, :archived_asset)
delegated_root = reflection(P206::Entry, :entryable)
delegated_all_rejected_root = reflection(P206::ArchiveOnlyEntry, :archive_subject)
primary_habtm = reflection(P206::PrimaryAuthor, :primary_tags)
archive_habtm = reflection(P206::ArchiveAuthor, :archive_tags)
cross_habtm = reflection(P206::PrimaryAuthor, :archive_tags)

payload = {
  'direct' => direct.transform_values do |item|
    {
      'macro' => item.macro.to_s,
      'target' => item.klass.name,
      'same_context' => same_context?(item.active_record, item.klass)
    }
  end,
  'through' => {
    'macro' => through.macro.to_s,
    'through_target' => through.through_reflection.klass.name,
    'source_target' => through.source_reflection.klass.name,
    'source_same_context' => same_context?(through.active_record, through.source_reflection.klass)
  },
  'polymorphic' => {
    'mixed_root' => polymorphic_root.polymorphic?,
    'all_rejected_root' => polymorphic_all_rejected_root.polymorphic?,
    'local_inverse_same_context' => same_context?(P206::Attachment, P206::LocalDocument),
    'archive_inverse_same_context' => same_context?(P206::Attachment, P206::ArchiveDocument)
  },
  'delegated_type' => {
    'mixed_root' => delegated_root.polymorphic?,
    'mixed_types' => P206::Entry.entryable_types,
    'all_rejected_root' => delegated_all_rejected_root.polymorphic?,
    'all_rejected_types' => P206::ArchiveOnlyEntry.archive_subject_types,
    'local_inverse_same_context' => same_context?(P206::Entry, P206::LocalArticle),
    'archive_inverse_same_context' => same_context?(P206::Entry, P206::ArchiveArticle)
  },
  'habtm' => {
    'primary_join_table' => primary_habtm.join_table,
    'archive_join_table' => archive_habtm.join_table,
    'same_hidden_name' => primary_habtm.join_table == archive_habtm.join_table,
    'primary_same_context' => same_context?(primary_habtm.active_record, primary_habtm.klass),
    'archive_same_context' => same_context?(archive_habtm.active_record, archive_habtm.klass),
    'cross_same_context' => same_context?(cross_habtm.active_record, cross_habtm.klass)
  }
}

output_root = Rails.root.join('tmp/rails_mmd')
FileUtils.mkdir_p(output_root)
File.write(output_root.join('cross_domain_runtime.json'), "#{JSON.pretty_generate(payload)}\n")
