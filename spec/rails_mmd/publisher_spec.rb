# frozen_string_literal: true

require 'json'
require 'tmpdir'
require 'rails_mmd/publisher'

# rubocop:disable RSpec/ExampleLength, RSpec/InstanceVariable, RSpec/MultipleExpectations
RSpec.describe RailsMmd::Publisher do
  around do |example|
    Dir.mktmpdir do |root|
      @project_root = Pathname(root)
      example.run
    end
  end

  let(:project_root) { @project_root }
  let(:publisher) { described_class.new(project_root: project_root) }

  it 'serializes pre-output fatal diagnostics to stderr and writes no files for invalid output dirs' do
    result = publisher.publish(output_dir: '/tmp/outside', selected_domain_ids: ['core'], diagnostics: [],
                               artifacts: {})

    expect(result).not_to be_success
    expect(result.diagnostics.first.fetch('code')).to eq('OUTPUT_DIRECTORY_INVALID')
    expect(JSON.parse(result.stderr).fetch('scope')).to eq('global')
    expect(project_root.children).to be_empty
  end

  it 'publishes diagnostics, Mermaid, and render plans inside a newly created output directory' do
    result = publisher.publish(
      output_dir: 'docs/rails_mmd',
      selected_domain_ids: ['core'],
      diagnostics: [warning_diagnostic],
      artifacts: { 'core' => { 'er' => er_artifact_without_diagnostics } }
    )

    output = project_root.join('docs/rails_mmd')
    expect(result).to be_success
    expect(output.join('core.diagnostics.json')).to exist
    expect(output.join('core.er.mmd').read).to eq(mermaid_fixture('er_markers_pk_fk.mmd'))
    expect(JSON.parse(output.join('core.er.render_plan.json').read).fetch('artifact_kind')).to eq('er')
    expect(output.children.map { |path| path.basename.to_s }).not_to include(a_string_starting_with('.rails-mmd-'))
  end

  it 'blocks all selected artifacts for invocation errors while still publishing diagnostics' do
    result = publisher.publish(
      output_dir: 'out',
      selected_domain_ids: ['core'],
      diagnostics: [rails_load_error],
      artifacts: { 'core' => { 'er' => er_artifact_without_diagnostics } }
    )

    output = project_root.join('out')
    expect(result).to be_success
    expect(output.join('global.diagnostics.json')).to exist
    expect(output.join('core.er.mmd')).not_to exist
    expect(output.join('core.er.render_plan.json')).not_to exist
  end

  it 'keeps pre-output fatal diagnostics on stderr only even when output dir is valid' do
    result = publisher.publish(
      output_dir: 'out',
      selected_domain_ids: ['core'],
      diagnostics: [invocation_error],
      artifacts: { 'core' => { 'er' => er_artifact_without_diagnostics } }
    )

    expect(result).not_to be_success
    expect(JSON.parse(result.stderr).fetch('diagnostics').first.fetch('code')).to eq('CONFIG_SCHEMA_INVALID')
    expect(project_root.join('out')).not_to exist
  end

  it 'blocks only the domain with domain errors and leaves unrelated user files untouched' do
    output = project_root.join('out')
    output.mkpath
    output.join('core.er.mmd').write('stale')
    output.join('admin.class.mmd').write('unselected')
    output.join('notes.txt').write('user file')

    result = publisher.publish(
      output_dir: 'out',
      selected_domain_ids: %w[core billing],
      diagnostics: [domain_error],
      artifacts: { 'core' => { 'er' => er_artifact_without_diagnostics }, 'billing' => { 'er' => billing_artifact } }
    )

    expect(result).to be_success
    expect(output.join('core.er.mmd')).not_to exist
    expect(output.join('billing.er.mmd')).to exist
    expect(output.join('admin.class.mmd').read).to eq('unselected')
    expect(output.join('notes.txt').read).to eq('user file')
  end

  it 'refuses final symlink targets and returns sanitized OUTPUT_WRITE_FAILED diagnostics' do
    output = project_root.join('out')
    output.mkpath
    output.join('core.diagnostics.json').write('old diagnostics')
    File.symlink(project_root.join('outside.mmd'), output.join('core.er.mmd'))

    result = publisher.publish(
      output_dir: 'out',
      selected_domain_ids: ['core'],
      diagnostics: [],
      artifacts: { 'core' => { 'er' => er_artifact_without_diagnostics } }
    )

    expect(result).not_to be_success
    expect(result.diagnostics.first.fetch('code')).to eq('OUTPUT_WRITE_FAILED')
    expect(output.join('core.diagnostics.json').read).to eq('old diagnostics')
    expect(JSON.generate(result.diagnostics)).not_to include(project_root.to_s)
  end

  it 'refuses existing directory targets without nesting artifacts inside them' do
    output = project_root.join('out')
    output.mkpath
    output.join('core.er.mmd').mkpath

    result = publisher.publish(
      output_dir: 'out',
      selected_domain_ids: ['core'],
      diagnostics: [],
      artifacts: { 'core' => { 'er' => er_artifact_without_diagnostics } }
    )

    expect(result).not_to be_success
    expect(output.join('core.er.mmd/core.er.mmd')).not_to exist
  end

  it 'rolls back existing managed files when replacement fails mid-publish' do
    output = project_root.join('out')
    output.mkpath
    output.join('core.er.mmd').write('old mermaid')
    output.join('core.er.render_plan.json').write('old plan')
    fail_render_plan_move_once

    result = publisher.publish(
      output_dir: 'out',
      selected_domain_ids: ['core'],
      diagnostics: [],
      artifacts: { 'core' => { 'er' => er_artifact_without_diagnostics } }
    )

    expect(result).not_to be_success
    expect(output.join('core.er.mmd').read).to eq('old mermaid')
    expect(output.join('core.er.render_plan.json').read).to eq('old plan')
  end

  it 'sorts diagnostics by severity, code, subject, and diagnostic id before writing' do
    publisher.publish(
      output_dir: 'out',
      selected_domain_ids: ['core'],
      diagnostics: ordered_diagnostics_examples,
      artifacts: {}
    )

    diagnostics = JSON.parse(project_root.join('out/core.diagnostics.json').read).fetch('diagnostics')
    expect(diagnostics.map { |diagnostic| diagnostic.fetch('diagnostic_id') })
      .to eq(%w[code_a id_a subject_a warning_a])
  end

  it 'ignores diagnostics and invalid artifacts for unselected domains' do
    result = publisher.publish(
      output_dir: 'out',
      selected_domain_ids: ['core'],
      diagnostics: [admin_domain_error],
      artifacts: { 'admin' => { 'er' => { render_plan: { 'bad' => true }, mermaid: 'bad' } } }
    )

    expect(result).to be_success
    expect(project_root.join('out/admin.diagnostics.json')).not_to exist
  end

  it 'rejects render plans with diagnostic references outside global or matching domain diagnostics' do
    result = publisher.publish(
      output_dir: 'out',
      selected_domain_ids: ['core'],
      diagnostics: [],
      artifacts: { 'core' => { 'er' => er_artifact } }
    )

    expect(result).not_to be_success
    expect(result.diagnostics.first.fetch('code')).to eq('OUTPUT_WRITE_FAILED')
  end

  def er_artifact
    { render_plan: render_plan_fixture('er'), mermaid: mermaid_fixture('er_markers_pk_fk.mmd') }
  end

  def er_artifact_without_diagnostics
    { render_plan: render_plan_fixture('er').merge('diagnostic_ids' => []),
      mermaid: mermaid_fixture('er_markers_pk_fk.mmd') }
  end

  def billing_artifact
    {
      render_plan: render_plan_fixture('er').merge('domain_id' => 'billing', 'diagnostic_ids' => []),
      mermaid: mermaid_fixture('er_markers_pk_fk.mmd')
    }
  end

  def fail_render_plan_move_once
    failed = false
    allow(FileUtils).to receive(:mv).and_wrap_original do |method, source, target|
      if !failed && target.end_with?('/out/core.er.render_plan.json')
        failed = true
        raise Errno::EACCES, source
      end

      method.call(source, target)
    end
  end

  def warning_diagnostic
    diagnostic('DB_METADATA_DEGRADED', 'warning', 'domain',
               { domain_id: 'core', ruby_constant: 'User', metadata_kind: 'foreign_key', reason: 'permission' })
  end

  def invocation_error
    diagnostic('CONFIG_SCHEMA_INVALID', 'error', 'invocation',
               { config_path: 'rails_mmd.yml', field_path: '$.domains' })
  end

  def rails_load_error
    diagnostic('RAILS_LOAD_FAILED', 'error', 'invocation',
               { exception_class: 'RuntimeError', exception_summary: 'load failed', backtrace: nil })
  end

  def domain_error
    diagnostic('DOMAIN_EMPTY', 'error', 'domain', { domain_id: 'core' })
  end

  def admin_domain_error
    diagnostic('DOMAIN_EMPTY', 'error', 'domain', { domain_id: 'admin' })
  end

  def ordered_diagnostics_examples
    [
      warning_diagnostic.merge('diagnostic_id' => 'warning_a'),
      model_table_missing('id_a', 'User'),
      model_table_missing('subject_a', 'Zebra'),
      domain_error.merge('diagnostic_id' => 'code_a')
    ]
  end

  def model_table_missing(diagnostic_id, ruby_constant)
    diagnostic(
      'MODEL_TABLE_MISSING',
      'error',
      'model',
      { domain_id: 'core', ruby_constant: ruby_constant, table_name: ruby_constant.downcase }
    ).merge('diagnostic_id' => diagnostic_id, 'subject_id' => ruby_constant)
  end

  def diagnostic(code, severity, _scope, metadata)
    RailsMmd::Diagnostics.new.build(
      code: code,
      severity: severity,
      subject_id: metadata[:domain_id],
      message: code.downcase.tr('_', ' '),
      metadata: metadata
    )
  end

  def render_plan_fixture(name)
    JSON.parse(Pathname("fixtures/schemas/render_plan/valid/#{name}.json").read)
  end

  def mermaid_fixture(name)
    Pathname("fixtures/mermaid/#{name}").read
  end
end
# rubocop:enable RSpec/ExampleLength, RSpec/InstanceVariable, RSpec/MultipleExpectations
