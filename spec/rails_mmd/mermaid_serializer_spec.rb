# frozen_string_literal: true

require 'json'
require 'rails_mmd/mermaid_serializer'
require 'rails_mmd/schema_validator'

RSpec.describe RailsMmd::MermaidSerializer do
  subject(:serializer) { described_class.new }

  it 'serializes ER markers, PK/FK attributes, and labels from render plans' do
    result = serializer.serialize(render_plan: render_plan_fixture('er').merge('comments' => []))

    aggregate_failures do
      expect(result.diagnostics).to be_empty
      expect(result.text).to eq(mermaid_fixture('er_markers_pk_fk.mmd'))
    end
  end

  it 'serializes ER standalone entities for attributes none without empty blocks' do
    result = serializer.serialize(render_plan: er_attributes_none_plan)

    expect_er_attributes_none(result)
  end

  it 'serializes class diagrams with direction, standalone classes, multiplicities, and labels' do
    result = serializer.serialize(render_plan: render_plan_fixture('class'))

    aggregate_failures do
      expect(result.diagnostics).to be_empty
      expect(result.text).to eq(mermaid_fixture('class_direction_and_labels.mmd'))
    end
  end

  it 'serializes class attribute blocks when render plans include key attributes' do
    result = serializer.serialize(render_plan: class_attributes_plan)

    expect(result.text).to include(
      "  class USER {\n    +bigint id\n    +bigint account_id\n  }\n"
    )
  end

  it 'serializes sanitized comments from render plans' do
    result = serializer.serialize(render_plan: class_standalone_comments_plan)

    aggregate_failures do
      expect(result.diagnostics).to be_empty
      expect(result.text).to eq(mermaid_fixture('class_standalone_and_comments.mmd'))
    end
  end

  it 'does not emit P1 Mermaid syntax or runtime validation hooks' do
    result = serializer.serialize(render_plan: render_plan_fixture('class'))

    expect(result.text).not_to match(/\bas\b|namespace|<\|--|\binterface\b|mmdc|mermaid-cli/i)
  end

  it 'converts serializer failures to schema-valid sanitized diagnostics' do
    plan = render_plan_fixture('er').merge('relationships' => [unlabeled_relationship])

    result = serializer.serialize(render_plan: plan)

    expect_failure_diagnostics(result)
  end

  it 'rejects schema-invalid render plans before rendering unsafe text' do
    result = serializer.serialize(render_plan: schema_invalid_secret_plan)

    expect_failure_diagnostics(result)
  end

  it 'keeps diagnostics schema-valid for malformed artifact and domain identifiers' do
    result = serializer.serialize(render_plan: malformed_identity_plan)

    expect_failure_diagnostics(result)
    expect_malformed_identity_fallback(result)
  end

  it 'keeps diagnostics schema-valid for non-hash input' do
    [nil, [], 'bad'].each do |render_plan|
      result = serializer.serialize(render_plan: render_plan)

      expect_failure_diagnostics(result)
      expect_malformed_identity_fallback(result)
    end
  end

  it 'rejects multiline render-plan labels and comments before interpolation' do
    %i[multiline_comment_plan multiline_relationship_label_plan multiline_attribute_label_plan].each do |plan_name|
      expect_failure_diagnostics(serializer.serialize(render_plan: public_send(plan_name)))
    end
  end

  def render_plan_fixture(name)
    JSON.parse(Pathname(__dir__).join("../../fixtures/schemas/render_plan/valid/#{name}.json").read)
  end

  def mermaid_fixture(name)
    Pathname(__dir__).join("../../fixtures/mermaid/#{name}").binread
  end

  def er_attributes_none_plan
    er_plan = render_plan_fixture('er')
    er_plan.merge(
      'direction' => 'TB',
      'entities' => er_plan.fetch('entities').map { |entity| entity.merge('attributes' => []) },
      'relationships' => [er_attributes_none_relationship(er_plan)],
      'comments' => []
    )
  end

  def er_attributes_none_relationship(er_plan)
    er_plan.fetch('relationships').first.merge(
      'er_left_marker' => '|o',
      'er_right_marker' => 'o{'
    )
  end

  def class_standalone_comments_plan
    er_plan = render_plan_fixture('er')
    er_plan.merge(
      'artifact_kind' => 'class',
      'relationships' => [],
      'comments' => [sanitized_comment],
      'entities' => er_plan.fetch('entities').map { |entity| entity.merge('attributes' => []) }
    )
  end

  def class_attributes_plan
    render_plan_fixture('er').merge('artifact_kind' => 'class', 'comments' => [], 'relationships' => [])
  end

  def sanitized_comment
    {
      'comment_id' => 'comments/sanitized',
      'safe_token' => 'COMMENT_SANITIZED',
      'text' => 'sanitized comment without sensitive data or paths'
    }
  end

  def schema_invalid_secret_plan
    render_plan_fixture('er').merge(
      'comments' => [
        render_plan_fixture('er').fetch('comments').first.merge('text' => '/Users/alice/.env token=abc')
      ]
    )
  end

  def malformed_identity_plan
    render_plan_fixture('er').merge('artifact_kind' => 'bad', 'domain_id' => 'BAD')
  end

  def multiline_comment_plan
    render_plan_fixture('er').merge(
      'comments' => [
        render_plan_fixture('er').fetch('comments').first.merge('text' => "line one\nline two")
      ]
    )
  end

  def multiline_relationship_label_plan
    render_plan_fixture('er').merge('relationships' => [unlabeled_relationship.merge('label' => "account\nbreak")])
  end

  def multiline_attribute_label_plan
    er_plan = render_plan_fixture('er').merge('comments' => [])
    er_plan.merge('entities' => [multiline_attribute_entity(er_plan), er_plan.fetch('entities').last])
  end

  def multiline_attribute_entity(er_plan)
    entity = er_plan.fetch('entities').first
    entity.merge(
      'attributes' => [
        entity.fetch('attributes').first.merge('label' => "id\nbreak")
      ]
    )
  end

  def unlabeled_relationship
    render_plan_fixture('er').fetch('relationships').first.merge('label' => '')
  end

  def expect_er_attributes_none(result)
    aggregate_failures do
      expect(result.diagnostics).to be_empty
      expect(result.text).to eq(mermaid_fixture('er_attributes_none.mmd'))
      expect(result.text).not_to include('{}')
    end
  end

  def expect_failure_diagnostics(result)
    aggregate_failures do
      expect_failure_result_shape(result)
      expect_failure_schema(result)
      expect_failure_redaction(result)
    end
  end

  def expect_failure_result_shape(result)
    expect(result.text).to be_nil
    expect(result.diagnostics.size).to eq(1)
    expect(result.diagnostics.first.fetch('code')).to eq('MERMAID_SERIALIZATION_FAILED')
  end

  def expect_failure_schema(result)
    expect(schema_valid_diagnostics?(result.diagnostics)).to be(true)
  end

  def expect_failure_redaction(result)
    expect(diagnostics_json(result)).not_to match(%r{/Users|raw_exception_backtrace|token=|secret=})
  end

  def expect_malformed_identity_fallback(result)
    aggregate_failures do
      expect(failure_subject_id(result)).to eq('global:er')
      expect(failure_metadata(result).fetch('artifact_kind')).to eq('er')
      expect(failure_metadata(result).fetch('domain_id')).to eq('global')
    end
  end

  def failure_subject_id(result)
    result.diagnostics.first.fetch('subject_id')
  end

  def failure_metadata(result)
    result.diagnostics.first.fetch('metadata')
  end

  def diagnostics_json(result)
    JSON.generate(result.diagnostics)
  end

  def schema_valid_diagnostics?(diagnostics)
    payload = {
      'schema_version' => 1,
      'scope' => 'domain',
      'domain_id' => 'core',
      'diagnostics' => diagnostics,
      'digest_sha256' => 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
    }
    RailsMmd::SchemaValidator.new.valid?(:diagnostics, payload)
  end
end
