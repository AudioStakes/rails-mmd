# frozen_string_literal: true

require 'active_record'
require 'json'
require 'tmpdir'

# Probe-only model declarations intentionally stay together so one temporary
# two-database topology is visible in a single executable record.
# rubocop:disable Metrics/BlockLength, Style/Documentation
Dir.mktmpdir('rails-mmd-p2-06-probe') do |directory|
  primary_database = File.join(directory, 'primary.sqlite3')
  archive_database = File.join(directory, 'archive.sqlite3')
  environment_name = ENV.fetch('RAILS_ENV', ENV.fetch('RACK_ENV', 'default_env'))

  ActiveRecord::Base.configurations = {
    environment_name => {
      'primary' => { 'adapter' => 'sqlite3', 'database' => primary_database },
      'primary_replica' => { 'adapter' => 'sqlite3', 'database' => primary_database, 'replica' => true },
      'archive' => { 'adapter' => 'sqlite3', 'database' => archive_database }
    }
  }

  class P206AppRecord < ActiveRecord::Base
    self.abstract_class = true
    connects_to database: { writing: :primary, reading: :primary_replica }
  end

  class P206ArchiveRecord < ActiveRecord::Base
    self.abstract_class = true
    connects_to database: { writing: :archive }
  end

  P206AppRecord.connection.create_table(:p206_accounts) { |table| table.string :name, null: false }
  P206AppRecord.connection.create_table(:p206_shared_rows) { |table| table.string :value }
  P206ArchiveRecord.connection.create_table(:p206_audits) do |table|
    table.integer :account_id, null: false
  end
  P206ArchiveRecord.connection.create_table(:p206_shared_rows) { |table| table.string :value }

  class P206Account < P206AppRecord
    self.table_name = 'p206_accounts'
    has_many :audits, class_name: 'P206Audit', foreign_key: 'account_id', inverse_of: :account
  end

  class P206Audit < P206ArchiveRecord
    self.table_name = 'p206_audits'
    belongs_to :account, class_name: 'P206Account', foreign_key: 'account_id', inverse_of: :audits
  end

  class P206PrimarySharedRow < P206AppRecord
    self.table_name = 'p206_shared_rows'
  end

  class P206ArchiveSharedRow < P206ArchiveRecord
    self.table_name = 'p206_shared_rows'
  end

  belongs_to_reflection = P206Audit.reflect_on_association(:account)
  has_many_reflection = P206Account.reflect_on_association(:audits)
  primary_config = P206Account.connection_db_config
  archive_config = P206Audit.connection_db_config
  reading_context = nil
  P206AppRecord.connected_to(role: :reading) do
    reading_config = P206Account.connection_db_config
    reading_context = {
      'name' => reading_config.name.to_s,
      'role' => P206Account.current_role.to_s,
      'shard' => P206Account.current_shard.to_s,
      'database' => reading_config.database.to_s
    }
  end

  payload = {
    'rails_version' => ActiveRecord.version.to_s,
    'reflections' => {
      'belongs_to' => {
        'klass' => belongs_to_reflection.klass.name,
        'foreign_key' => belongs_to_reflection.foreign_key.to_s,
        'association_primary_key' => belongs_to_reflection.association_primary_key.to_s
      },
      'has_many' => {
        'klass' => has_many_reflection.klass.name,
        'foreign_key' => has_many_reflection.foreign_key.to_s,
        'association_primary_key' => has_many_reflection.association_primary_key.to_s
      }
    },
    'contexts' => {
      'primary' => {
        'name' => primary_config.name.to_s,
        'role' => P206Account.current_role.to_s,
        'shard' => P206Account.current_shard.to_s,
        'database' => primary_config.database.to_s
      },
      'archive' => {
        'name' => archive_config.name.to_s,
        'role' => P206Audit.current_role.to_s,
        'shard' => P206Audit.current_shard.to_s,
        'database' => archive_config.database.to_s
      },
      'reading' => reading_context,
      'primary_vs_archive_same_database' => primary_config.database.to_s == archive_config.database.to_s,
      'primary_vs_archive_same_context' => primary_config.name.to_s == archive_config.name.to_s &&
                                           primary_config.database.to_s == archive_config.database.to_s,
      'primary_vs_reading_same_database' => primary_config.database.to_s == reading_context.fetch('database'),
      'primary_vs_reading_same_context' => primary_config.name.to_s == reading_context.fetch('name') &&
                                           P206Account.current_role.to_s == reading_context.fetch('role')
    },
    'database_evidence' => {
      'primary_foreign_keys_for_archive_table' => P206Account.connection.foreign_keys('p206_audits').length,
      'archive_foreign_keys_for_owner_table' => P206Audit.connection.foreign_keys('p206_accounts').length
    },
    'identity_collision' => {
      'same_table_name' => P206PrimarySharedRow.table_name == P206ArchiveSharedRow.table_name,
      'different_context_name' => P206PrimarySharedRow.connection_db_config.name.to_s !=
                                  P206ArchiveSharedRow.connection_db_config.name.to_s
    }
  }

  puts JSON.generate(payload)
ensure
  P206AppRecord.remove_connection if defined?(P206AppRecord)
  P206ArchiveRecord.remove_connection if defined?(P206ArchiveRecord)
end
# rubocop:enable Metrics/BlockLength, Style/Documentation
