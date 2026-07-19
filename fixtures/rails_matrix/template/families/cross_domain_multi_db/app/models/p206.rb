# frozen_string_literal: true

# Real multi-database association topology used by the P2-06 matrix family.
# rubocop:disable Style/Documentation
module P206
  class ArchiveRecord < ActiveRecord::Base
    self.abstract_class = true
    connects_to database: { writing: :archive }
  end

  class Account < ApplicationRecord
    self.table_name = 'p206_accounts'

    has_many :orders, class_name: 'P206::Order', foreign_key: :account_id, inverse_of: :account
    has_many :audits, class_name: 'P206::Audit', foreign_key: :account_id, inverse_of: :account
    has_one :archive_profile, class_name: 'P206::ArchiveProfile', foreign_key: :account_id, inverse_of: :account
    has_many :memberships, class_name: 'P206::Membership', foreign_key: :account_id, inverse_of: :account
    has_many :archive_notes, through: :memberships, source: :archive_note
    has_many :shared_targets, class_name: 'P206::SharedTarget', foreign_key: :account_id
    has_many :external_targets, class_name: 'P206::ExternalTarget', foreign_key: :account_id
  end

  class Order < ApplicationRecord
    self.table_name = 'p206_orders'
    belongs_to :account, class_name: 'P206::Account', inverse_of: :orders
  end

  class Audit < ArchiveRecord
    self.table_name = 'p206_audits'
    belongs_to :account, class_name: 'P206::Account', inverse_of: :audits
  end

  class ArchiveProfile < ArchiveRecord
    self.table_name = 'p206_archive_profiles'
    belongs_to :account, class_name: 'P206::Account', inverse_of: :archive_profile
  end

  class Membership < ApplicationRecord
    self.table_name = 'p206_memberships'
    belongs_to :account, class_name: 'P206::Account', inverse_of: :memberships
    belongs_to :archive_note, class_name: 'P206::ArchiveNote'
  end

  class ArchiveNote < ArchiveRecord
    self.table_name = 'p206_archive_notes'
  end

  class SharedTarget < ApplicationRecord
    self.table_name = 'p206_shared_targets'
  end

  class ExternalTarget < ArchiveRecord
    self.table_name = 'p206_external_targets'
  end

  class Attachment < ApplicationRecord
    self.table_name = 'p206_attachments'
    belongs_to :attachable, polymorphic: true
  end

  class LocalDocument < ApplicationRecord
    self.table_name = 'p206_local_documents'
    has_many :attachments, as: :attachable, class_name: 'P206::Attachment'
  end

  class ArchiveDocument < ArchiveRecord
    self.table_name = 'p206_archive_documents'
    has_many :attachments, as: :attachable, class_name: 'P206::Attachment'
  end

  class ArchiveOnlyAttachment < ApplicationRecord
    self.table_name = 'p206_archive_only_attachments'
    belongs_to :archived_asset, polymorphic: true
  end

  class ArchiveAsset < ArchiveRecord
    self.table_name = 'p206_archive_assets'
    has_many :archive_only_attachments,
             as: :archived_asset,
             class_name: 'P206::ArchiveOnlyAttachment'
  end

  class Entry < ApplicationRecord
    self.table_name = 'p206_entries'
    delegated_type :entryable, types: %w[P206::LocalArticle P206::ArchiveArticle]
  end

  class LocalArticle < ApplicationRecord
    self.table_name = 'p206_local_articles'
    has_one :entry, as: :entryable, class_name: 'P206::Entry'
  end

  class ArchiveArticle < ArchiveRecord
    self.table_name = 'p206_archive_articles'
    has_one :entry, as: :entryable, class_name: 'P206::Entry'
  end

  class ArchiveOnlyEntry < ApplicationRecord
    self.table_name = 'p206_archive_only_entries'
    delegated_type :archive_subject, types: %w[P206::ArchiveOnlyArticle]
  end

  class ArchiveOnlyArticle < ArchiveRecord
    self.table_name = 'p206_archive_only_articles'
    has_one :archive_only_entry, as: :archive_subject, class_name: 'P206::ArchiveOnlyEntry'
  end

  class PrimaryAuthor < ApplicationRecord
    self.table_name = 'p206_primary_authors'
    has_and_belongs_to_many :primary_tags,
                            class_name: 'P206::PrimaryTag',
                            join_table: 'p206_shared_links',
                            foreign_key: :author_id,
                            association_foreign_key: :tag_id
    has_and_belongs_to_many :archive_tags,
                            class_name: 'P206::ArchiveTag',
                            join_table: 'p206_cross_links',
                            foreign_key: :author_id,
                            association_foreign_key: :tag_id
  end

  class PrimaryTag < ApplicationRecord
    self.table_name = 'p206_primary_tags'
  end

  class ArchiveAuthor < ArchiveRecord
    self.table_name = 'p206_archive_authors'
    has_and_belongs_to_many :archive_tags,
                            class_name: 'P206::ArchiveTag',
                            join_table: 'p206_shared_links',
                            foreign_key: :author_id,
                            association_foreign_key: :tag_id
  end

  class ArchiveTag < ArchiveRecord
    self.table_name = 'p206_archive_tags'
  end

  class PrimaryCollision < ApplicationRecord
    self.table_name = 'p206_collision_rows'
  end

  class ArchiveCollision < ArchiveRecord
    self.table_name = 'p206_collision_rows'
  end
end
# rubocop:enable Style/Documentation
