# frozen_string_literal: true

require 'spec_helper'
require 'rails_mmd/artifact_refs'
require 'rails_mmd/diagnostics'
require 'rails_mmd/generate'
require 'rails_mmd/ordering'
require 'rails_mmd/safe_tokens'
require 'rails_mmd/verification_routing'

RSpec.describe RailsMmd, :aggregate_failures do
  it 'keeps the former class names as compatibility aliases' do
    expect(RailsMmd::ArtifactRefs).to equal(RailsMmd::ArtifactRefSanitizer)
    expect(RailsMmd::Diagnostics).to equal(RailsMmd::DiagnosticFactory)
    expect(RailsMmd::Generate).to equal(RailsMmd::GenerateCommand)
    expect(RailsMmd::SafeTokens).to equal(RailsMmd::SafeTokenAssigner)
    expect(RailsMmd::VerificationRouting).to equal(RailsMmd::VerificationRunner)
  end

  it 'keeps the former method and nested constant interfaces available' do
    expect(RailsMmd::GenerationPipeline.instance_methods(false)).to include(:build, :generate)
    expect(RailsMmd::Ordering).to respond_to(:by_key, :diagnostics, :sort_by_key, :sort_diagnostics)
    expect(RailsMmd::OutputDirectory::Result).to equal(RailsMmd::OutputDirectory::Resolution)
  end

  it 'keeps former constant and config field readers available' do
    expect(RailsMmd::AttributeTypes::SUPPORTED).to equal(RailsMmd::AttributeTypes::SUPPORTED_TYPES)
    expect(RailsMmd::ExitPolicy::CODE_BY_DIAGNOSTIC)
      .to equal(RailsMmd::ExitPolicy::EXIT_CODE_BY_DIAGNOSTIC_CODE)

    domain = RailsMmd::Config::Domain.new(id: 'core', include_models: [], exclude_models: [])
    expect(domain).to have_attributes(id: 'core', domain_id: 'core')
  end
end
