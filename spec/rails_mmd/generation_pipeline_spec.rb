# frozen_string_literal: true

require 'rails_mmd/config'
require 'rails_mmd/generation_pipeline'

# rubocop:disable Lint/ConstantDefinitionInBlock, Naming/MethodParameterName, RSpec/InstanceVariable, RSpec/LeakyConstantDeclaration, RSpec/MultipleExpectations
RSpec.describe RailsMmd::GenerationPipeline do
  StageResult = Struct.new(:payload, :diagnostics)
  SerializationResult = Struct.new(:text, :diagnostics)

  class FakeRenderPlanBuilder
    def initialize(diagnostics: [])
      @diagnostics = diagnostics
    end

    def build(ir:, artifact_kind:, **)
      StageResult.new({ 'domain_id' => ir.fetch('domain_id'), 'artifact_kind' => artifact_kind }, @diagnostics)
    end
  end

  class FakeMermaidSerializer
    def initialize(diagnostics: [])
      @diagnostics = diagnostics
    end

    def serialize(render_plan:)
      SerializationResult.new("#{render_plan.fetch('artifact_kind')}Diagram\n", @diagnostics)
    end
  end

  class PrefixingRedactor < RailsMmd::Redactor
    def sanitize(value)
      "shared:#{super}"
    end
  end

  it 'runs the real in-process stages through one interface' do
    result = described_class.new(active_record_base: empty_active_record_base).build(config: config)

    expect_pipeline_result(result)
  end

  it 'uses one redaction policy across the in-process stages' do
    redactor = PrefixingRedactor.new(project_root: Dir.pwd, env: {})
    result = described_class.new(active_record_base: empty_active_record_base, redactor: redactor)
                            .build(config: config)

    expect(result.diagnostics.fetch(0).fetch('message')).to start_with('shared:')
  end

  it 'accumulates render-plan diagnostics through the pipeline interface' do
    result = pipeline(render_plan_diagnostics: [diagnostic('SAFE_TOKEN_COLLISION')]).build(config: config(format: 'er'))

    expect(result.diagnostics.map { |item| item.fetch('code') }).to eq(%w[DOMAIN_EMPTY SAFE_TOKEN_COLLISION])
    expect(result.artifacts.fetch('core')).to include('er')
  end

  it 'accumulates serialization diagnostics and omits the failed artifact' do
    result = pipeline(serializer_diagnostics: [diagnostic('MERMAID_SERIALIZATION_FAILED')])
             .build(config: config(format: 'er'))

    expect(result.diagnostics.map { |item| item.fetch('code') }).to eq(%w[DOMAIN_EMPTY MERMAID_SERIALIZATION_FAILED])
    expect(result.artifacts.fetch('core')).to be_empty
  end

  def expect_pipeline_result(result)
    artifact = include(:render_plan, :mermaid)
    expect(result).to have_attributes(
      diagnostics: contain_exactly(include('code' => 'DOMAIN_EMPTY')),
      artifacts: include('core' => include('er' => artifact, 'class' => artifact))
    )
  end

  def pipeline(render_plan_diagnostics: [], serializer_diagnostics: [])
    described_class.new(
      active_record_base: empty_active_record_base,
      render_plan_builder: FakeRenderPlanBuilder.new(diagnostics: render_plan_diagnostics),
      mermaid_serializer: FakeMermaidSerializer.new(diagnostics: serializer_diagnostics)
    )
  end

  def empty_active_record_base
    Class.new do
      def self.descendants = []
    end
  end

  def config(format: 'both')
    output = RailsMmd::Config::Output.new(directory: 'out', format: format, attributes: 'keys', direction: 'LR')
    domain = RailsMmd::Config::Domain.new(id: 'core', include_models: [], exclude_models: [])
    RailsMmd::Config::Resolved.new(domains: { 'core' => domain }, output: output, selected_domain_ids: ['core'])
  end

  def diagnostic(code)
    diagnostics_catalog.find { |item| item.fetch('code') == code }.dup
  end

  def diagnostics_catalog
    @diagnostics_catalog ||= JSON.parse(
      File.read('fixtures/schemas/diagnostics/valid/catalog.json')
    ).fetch('diagnostics')
  end
end
# rubocop:enable Lint/ConstantDefinitionInBlock, Naming/MethodParameterName, RSpec/InstanceVariable, RSpec/LeakyConstantDeclaration, RSpec/MultipleExpectations
