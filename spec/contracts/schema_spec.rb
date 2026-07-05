# frozen_string_literal: true

require 'json'
require 'json_schemer'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'P0 contract schemas' do
  def schema_root
    Pathname(__dir__).join('../../schemas').expand_path
  end

  def fixture_root
    Pathname(__dir__).join('../../fixtures/schemas').expand_path
  end

  def load_json(path)
    JSON.parse(Pathname(path).read)
  end

  def schema(name)
    JSONSchemer.schema(load_json(schema_root.join("#{name}.schema.json")))
  end

  def fixture(path)
    load_json(fixture_root.join(path))
  end

  def expect_valid(schema_name, fixture_path)
    expect(schema(schema_name)).to be_valid(fixture(fixture_path))
  end

  def expect_invalid(schema_name, fixture_path)
    expect(schema(schema_name)).not_to be_valid(fixture(fixture_path))
  end

  describe 'config.schema.json' do
    it 'accepts complete and defaultable config fixtures' do
      config_valid_fixtures.each { |path| expect_valid('config', path) }
    end

    it 'rejects unknown fields and invalid include models' do
      config_invalid_fixtures.each { |path| expect_invalid('config', path) }
    end

    it 'matches the canonical domain id grammar examples' do
      examples = fixture('config/domain_id_examples.json')

      expect(domain_id_results(examples)).to eq(
        'positive' => examples.fetch('positive'),
        'negative' => []
      )
    end

    it 'rejects line terminators and surrounding/control whitespace in domain IDs' do
      invalid_ids = fixture('config/domain_id_examples.json').fetch('negative')

      expect(valid_domain_ids(invalid_ids.grep(/\s/))).to be_empty
    end
  end

  describe 'diagnostics.schema.json' do
    it 'accepts a fixture covering the closed diagnostic catalog' do
      expect_valid('diagnostics', 'diagnostics/valid/catalog.json')
    end

    it 'rejects diagnostics outside the closed catalog and sanitized boundary' do
      diagnostics_invalid_fixtures.each { |path| expect_invalid('diagnostics', path) }
    end

    it 'covers every diagnostic code from the P0 catalog fixture' do
      catalog = fixture('diagnostics/valid/catalog.json').fetch('diagnostics')
      codes = catalog.map { |diagnostic| diagnostic.fetch('code') }

      expect(codes).to match_array(diagnostic_codes_from_schema)
    end
  end

  describe 'ir.schema.json' do
    it 'accepts Mermaid-independent IR with digest and no safe tokens' do
      expect_valid('ir', 'ir/valid/core.json')
      expect(JSON.generate(fixture('ir/valid/core.json'))).not_to include('safe_token')
    end

    it 'rejects safe tokens and invalid digest boundaries' do
      ir_invalid_fixtures.each { |path| expect_invalid('ir', path) }
    end
  end

  describe 'render_plan.schema.json' do
    it 'accepts render plans covering safe tokens, markers, multiplicities, and diagnostics' do
      %w[render_plan/valid/er.json render_plan/valid/class.json].each do |path|
        expect_valid('render_plan', path)
      end
    end

    it 'rejects invalid digest boundaries and machine-local fields' do
      render_plan_invalid_fixtures.each { |path| expect_invalid('render_plan', path) }
    end
  end

  it 'rejects whitespace and line terminators in every domain-scoped schema domain ID' do
    invalid_ids = fixture('config/domain_id_examples.json').fetch('negative').grep(/\s/)

    expect(domain_schema_acceptances(invalid_ids)).to all(eq([]))
  end

  def config_valid_fixtures
    %w[
      config/valid/full.json
      config/valid/attributes_none_er_tb.json
      config/valid/class_bt.json
    ]
  end

  def config_invalid_fixtures
    %w[
      config/invalid/unknown_top_level.json
      config/invalid/unknown_domain_field.json
      config/invalid/unknown_output_field.json
      config/invalid/empty_include_models.json
    ]
  end

  def ir_invalid_fixtures
    %w[
      ir/invalid/contains_safe_token.json
      ir/invalid/uppercase_digest.json
      ir/invalid/short_digest.json
      ir/invalid/long_digest.json
      ir/invalid/non_hex_digest.json
      ir/invalid/missing_digest.json
      ir/invalid/machine_local_fields.json
    ]
  end

  def diagnostics_invalid_fixtures
    diagnostics_digest_invalid_fixtures + diagnostics_sanitized_invalid_fixtures
  end

  def diagnostics_digest_invalid_fixtures
    %w[
      diagnostics/invalid/unknown_code.json
      diagnostics/invalid/uppercase_digest.json
      diagnostics/invalid/short_digest.json
      diagnostics/invalid/long_digest.json
      diagnostics/invalid/non_hex_digest.json
      diagnostics/invalid/missing_digest.json
    ]
  end

  def diagnostics_sanitized_invalid_fixtures
    %w[
      diagnostics/invalid/invalid_domain_id.json
      diagnostics/invalid/global_domain_mismatch.json
      diagnostics/invalid/machine_local_metadata.json
      diagnostics/invalid/absolute_artifact_path.json
      diagnostics/invalid/raw_backtrace.json
    ]
  end

  def render_plan_invalid_fixtures
    render_plan_digest_invalid_fixtures + render_plan_sanitized_invalid_fixtures
  end

  def render_plan_digest_invalid_fixtures
    %w[
      render_plan/invalid/uppercase_digest.json
      render_plan/invalid/short_digest.json
      render_plan/invalid/long_digest.json
      render_plan/invalid/non_hex_digest.json
      render_plan/invalid/missing_digest.json
    ]
  end

  def render_plan_sanitized_invalid_fixtures
    %w[
      render_plan/invalid/missing_attribute_type.json
      render_plan/invalid/unsupported_attribute_type.json
      render_plan/invalid/machine_local_fields.json
      render_plan/invalid/unsanitized_comment.json
      render_plan/invalid/redacted_key_value_comment.json
    ]
  end

  def domain_id_results(examples)
    examples.transform_values { |domain_ids| valid_domain_ids(domain_ids) }
  end

  def valid_domain_ids(domain_ids)
    domain_ids.select { |domain_id| domain_id_valid?(domain_id) }
  end

  def domain_schema_acceptances(domain_ids)
    [
      domain_ids.select { |domain_id| diagnostics_domain_id_valid?(domain_id) },
      domain_ids.select { |domain_id| ir_domain_id_valid?(domain_id) },
      domain_ids.select { |domain_id| render_plan_domain_id_valid?(domain_id) }
    ]
  end

  def domain_id_valid?(domain_id)
    data = {
      'version' => 1,
      'domains' => {
        domain_id => { 'include_models' => ['User'] }
      }
    }

    schema('config').valid?(data)
  end

  def diagnostics_domain_id_valid?(domain_id)
    data = {
      'schema_version' => 1,
      'scope' => 'domain',
      'domain_id' => domain_id,
      'diagnostics' => [],
      'digest_sha256' => digest('a')
    }

    schema('diagnostics').valid?(data)
  end

  def ir_domain_id_valid?(domain_id)
    data = {
      'schema_version' => 1,
      'domain_id' => domain_id,
      'entities' => [],
      'relationships' => [],
      'diagnostic_ids' => [],
      'digest_sha256' => digest('b')
    }

    schema('ir').valid?(data)
  end

  def render_plan_domain_id_valid?(domain_id)
    schema('render_plan').valid?(render_plan_with_domain_id(domain_id))
  end

  def render_plan_with_domain_id(domain_id)
    render_plan_base.merge('domain_id' => domain_id)
  end

  def render_plan_base
    {
      'schema_version' => 1, 'artifact_kind' => 'er', 'domain_id' => 'core', 'direction' => 'LR',
      'entities' => [],
      'relationships' => [],
      'comments' => [],
      'diagnostic_ids' => [],
      'digest_sha256' => digest('c')
    }
  end

  def digest(character)
    character * 64
  end

  def diagnostic_codes_from_schema
    schema_json = load_json(schema_root.join('diagnostics.schema.json'))
    schema_json.fetch('$defs').fetch('diagnostic_code').fetch('enum')
  end
end
# rubocop:enable RSpec/DescribeClass
