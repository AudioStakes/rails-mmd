# frozen_string_literal: true

require 'rails_mmd/relationship_metadata'

# rubocop:disable Metrics/ParameterLists, RSpec/ExampleLength, RSpec/MultipleExpectations
RSpec.describe RailsMmd::RelationshipMetadata do
  let(:reflection_class) { Struct.new(:options, :counter_cache_column, keyword_init: true) }

  def metadata_for(
    options, macro: :belongs_to, through: false, direction: :from_owner,
    column: nil, scoped: false, name: 'account'
  )
    described_class.for_declaration(
      reflection: reflection_class.new(options: options, counter_cache_column: column),
      association_name: name, association_macro: macro, through: through,
      direction: direction, scoped: scoped
    )
  end

  it 'normalizes and freezes a belongs-to dependent declaration from the canonical owner' do
    metadata = described_class.for_declaration(
      reflection: reflection_class.new(options: { dependent: :delete }),
      association_name: 'account',
      association_macro: :belongs_to,
      through: false,
      direction: :from_owner,
      scoped: false
    )

    expect(metadata).to eq(
      behavior: {
        from_owner: [
          {
            association_name: 'account',
            association_macro: 'belongs_to',
            dependent: { action: 'delete', target: 'associated_records' }
          }
        ]
      }
    )
    expect(metadata).to be_frozen
    expect(metadata.dig(:behavior, :from_owner)).to be_frozen
    expect(metadata.dig(:behavior, :from_owner, 0, :dependent)).to be_frozen
  end

  it 'accepts the supported dependent enum as a reflected string' do
    metadata = metadata_for({ dependent: 'destroy_async' })

    expect(metadata.dig(:behavior, :from_owner, 0, :dependent)).to eq(
      action: 'destroy_async', target: 'associated_records'
    )
  end

  it 'normalizes default and named touch without publishing invalid values' do
    default_touch = metadata_for({ touch: true })
    named_touch = metadata_for({ touch: :account_touched_at })
    invalid_touch = metadata_for({ touch: 'not a column' })

    expect(default_touch.dig(:behavior, :from_owner, 0, :touch)).to eq(attribute: nil)
    expect(named_touch.dig(:behavior, :from_owner, 0, :touch)).to eq(attribute: 'account_touched_at')
    expect(invalid_touch).to be_nil
  end

  it 'normalizes active and inactive belongs-to counter caches from Rails metadata' do
    active = metadata_for({ counter_cache: { active: true, column: nil } }, column: 'members_count')
    inactive = metadata_for(
      { counter_cache: { active: false, column: 'custom_members_count' } },
      column: 'custom_members_count'
    )

    expect(active.dig(:behavior, :from_owner, 0, :counter_cache)).to eq(
      column: 'members_count', active: true
    )
    expect(inactive.dig(:behavior, :from_owner, 0, :counter_cache)).to eq(
      column: 'custom_members_count', active: false
    )
  end

  it 'contains unreadable options and counter readers without losing readable behavior' do
    unreadable_options = Object.new.tap do |reflection|
      reflection.define_singleton_method(:options) { raise 'unreadable options' }
    end
    unreadable_counter = reflection_class.new(
      options: { dependent: :delete, counter_cache: { active: true, column: nil } }
    ).tap do |reflection|
      reflection.define_singleton_method(:counter_cache_column) { raise 'unreadable counter' }
    end

    absent = described_class.for_declaration(
      reflection: unreadable_options, association_name: 'account', association_macro: :belongs_to,
      through: false, direction: :from_owner, scoped: false
    )
    partial = described_class.for_declaration(
      reflection: unreadable_counter, association_name: 'account', association_macro: :belongs_to,
      through: false, direction: :from_owner, scoped: false
    )

    expect(absent).to be_nil
    expect(partial.dig(:behavior, :from_owner, 0)).to eq(
      association_name: 'account', association_macro: 'belongs_to',
      dependent: { action: 'delete', target: 'associated_records' }
    )
  end

  it 'applies macro and through-specific behavior rules' do
    direct_has_one = metadata_for(
      { dependent: :nullify, touch: :profile_touched_at }, macro: :has_one, direction: :from_target
    )
    through_has_one = metadata_for(
      { dependent: :destroy, touch: true }, macro: :has_one, through: true
    )
    through_has_many = metadata_for({ dependent: :delete_all }, macro: :has_many, through: true)
    inverse_counter = metadata_for(
      { counter_cache: { active: true, column: 'members_count' } },
      macro: :has_many, column: 'members_count'
    )

    expect(direct_has_one.dig(:behavior, :from_target, 0)).to include(
      dependent: { action: 'nullify', target: 'associated_records' },
      touch: { attribute: 'profile_touched_at' }
    )
    expect(through_has_one.dig(:behavior, :from_owner, 0)).not_to have_key(:dependent)
    expect(through_has_one.dig(:behavior, :from_owner, 0, :touch)).to eq(attribute: nil)
    expect(through_has_many.dig(:behavior, :from_owner, 0, :dependent)).to eq(
      action: 'delete_all', target: 'through_records'
    )
    expect(inverse_counter).to be_nil
  end

  it 'merges scope and both directions with exact deduplication and canonical ordering' do
    owner_zeta = metadata_for({ dependent: :delete }, name: 'zeta_account')
    owner_alpha = metadata_for({ dependent: :destroy }, name: 'alpha_account')
    target = metadata_for(
      { dependent: :nullify }, macro: :has_many, direction: :from_target, name: 'members'
    )

    merged = described_class.merge(
      target, owner_zeta, described_class.scoped(true), owner_alpha, owner_zeta
    )

    expect(merged.fetch(:scoped)).to be(true)
    expect(merged.dig(:behavior, :from_owner).map { |item| item.fetch(:association_name) }).to eq(
      %w[alpha_account zeta_account]
    )
    expect(merged.dig(:behavior, :from_target)).to contain_exactly(
      include(association_name: 'members')
    )
    expect(merged).to be_frozen
  end

  it 'omits empty metadata and projects the closed public JSON shape' do
    internal = described_class.merge(
      described_class.scoped(true),
      metadata_for(
        {
          dependent: :delete, touch: true,
          counter_cache: { active: false, column: 'members_count' }
        },
        name: 'account', column: 'members_count'
      ),
      metadata_for(
        { dependent: :nullify },
        macro: :has_many, direction: :from_target, name: 'members'
      )
    )

    expect(described_class.scoped(false)).to be_nil
    expect(described_class.merge(nil, nil)).to be_nil
    expect(described_class.public_payload(internal)).to eq(
      'scoped' => true,
      'behavior' => {
        'from_owner' => [
          {
            'association_name' => 'account',
            'association_macro' => 'belongs_to',
            'dependent' => { 'action' => 'delete', 'target' => 'associated_records' },
            'touch' => { 'attribute' => nil },
            'counter_cache' => { 'column' => 'members_count', 'active' => false }
          }
        ],
        'from_target' => [
          {
            'association_name' => 'members',
            'association_macro' => 'has_many',
            'dependent' => { 'action' => 'nullify', 'target' => 'associated_records' }
          }
        ]
      }
    )
  end
end
# rubocop:enable Metrics/ParameterLists, RSpec/ExampleLength, RSpec/MultipleExpectations
