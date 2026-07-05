# frozen_string_literal: true

require 'rails_mmd/canonical_json'
require 'rails_mmd/config'
require 'rails_mmd/domain_resolver'
require 'rails_mmd/model_inventory'
require 'rails_mmd/schema_validator'

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
RSpec.describe RailsMmd::DomainResolver do
  it 'selects configured domains exactly and subtracts excludes before schema probing' do
    user = record('User')
    account = record('Account')
    invoice = record('Billing::Invoice')
    config = config_for({
                          'core' => { include: %w[User Account], exclude: ['Account'] },
                          'billing' => { include: ['Billing::Invoice'], exclude: [] }
                        })

    result = described_class.new.resolve(config: config, inventory_records: [user, account, invoice])

    expect(result).to be_success
    expect(result.exit_code).to eq(0)
    expect(result.domains.map(&:domain_id)).to eq(%w[core billing])
    expect(result.domains.map { |domain| domain.records.map(&:ruby_constant) }).to eq([['User'], ['Billing::Invoice']])
  end

  it 'respects a future selected domain from config loading' do
    config = config_for(
      {
        'core' => { include: ['User'], exclude: [] },
        'admin' => { include: ['Admin::User'], exclude: [] }
      },
      selected_domain_ids: ['admin']
    )

    result = described_class.new.resolve(config: config, inventory_records: [record('User'), record('Admin::User')])

    expect(result).to be_success
    expect(result.domains.map(&:domain_id)).to eq(['admin'])
    expect(result.domains.first.records.map(&:ruby_constant)).to eq(['Admin::User'])
  end

  it 'emits schema-valid diagnostics for missing, non-renderable, and empty domains' do
    abstract = record('ApplicationRecord', renderable: false, reason: 'abstract_class')
    sti = record('Dog', renderable: false, reason: 'sti_subclass')
    config = config_for({
                          'core' => { include: %w[MissingModel ApplicationRecord], exclude: ['Dog'] },
                          'empty_domain' => { include: ['User'], exclude: ['User'] }
                        })

    result = described_class.new.resolve(config: config, inventory_records: [abstract, sti, record('User')])

    expect(result).not_to be_success
    expect(result.exit_code).to eq(2)
    expect(result.diagnostics.map { |diagnostic| diagnostic.fetch('code') }).to eq(
      %w[
        DOMAIN_MODEL_NOT_FOUND
        DOMAIN_MODEL_NOT_RENDERABLE
        DOMAIN_MODEL_NOT_RENDERABLE
        DOMAIN_EMPTY
        DOMAIN_EMPTY
      ]
    )
    expect(result.diagnostics).to all(satisfy { |diagnostic| schema_valid_diagnostic?(diagnostic) })
    expect(result.domains.map { |domain| [domain.domain_id, domain.records] }).to eq(
      [['core', []], ['empty_domain', []]]
    )
  end

  def config_for(domain_data, selected_domain_ids: nil)
    selected_domain_ids ||= domain_data.keys

    RailsMmd::Config::Resolved.new(
      domains: domain_data.to_h { |domain_id, domain| [domain_id, config_domain(domain_id, domain)] },
      selected_domain_ids: selected_domain_ids
    )
  end

  def config_domain(domain_id, domain)
    RailsMmd::Config::Domain.new(
      id: domain_id,
      include_models: domain.fetch(:include),
      exclude_models: domain.fetch(:exclude)
    )
  end

  def record(ruby_constant, renderable: true, reason: nil, connection_context_id: '{"name":"primary"}')
    RailsMmd::ModelInventory::Record.new(
      ruby_constant: ruby_constant,
      abstract_class: reason == 'abstract_class',
      base_class: ruby_constant,
      table_name: ruby_constant.split('::').last.downcase,
      connection_context_id: connection_context_id,
      renderable: renderable,
      renderability_reason: reason
    )
  end

  def schema_valid_diagnostic?(diagnostic)
    envelope = {
      'schema_version' => 1,
      'scope' => 'domain',
      'domain_id' => diagnostic.fetch('metadata').fetch('domain_id'),
      'diagnostics' => [diagnostic],
      'digest_sha256' => RailsMmd::CanonicalJson.digest_sha256(diagnostic)
    }

    RailsMmd::SchemaValidator.new.valid?(:diagnostics, envelope)
  end
end
# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
