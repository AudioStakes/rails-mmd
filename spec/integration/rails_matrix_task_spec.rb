# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'the Rails compatibility matrix Rake command' do
  let(:invalid_artifact_asdf) do
    <<~'SH'
      [ "$1" = "where" ] && exit 0
      case "$*" in
        *--version*) exit 0 ;;
        *"exec rails-mmd generate"*)
          mkdir -p tmp/rails_mmd
          printf 'erDiagram\n' > tmp/rails_mmd/core.er.mmd
          printf 'classDiagram\n' > tmp/rails_mmd/core.class.mmd
          printf '{}\n' > tmp/rails_mmd/core.er.render_plan.json
          printf '{}\n' > tmp/rails_mmd/core.class.render_plan.json
          exit 0 ;;
        *) exit 0 ;;
      esac
    SH
  end

  let(:selected_pair_asdf) do
    <<~SH
      [ "$1 $2 $3" = "where ruby 4.0.6" ] && exit 0
      [ "$1" = "where" ] && exit 1
      case "$*" in
        *--version*) exit 0 ;;
        *) exit 0 ;;
      esac
    SH
  end

  let(:malformed_mermaid_asdf) do
    <<~'SH'
      [ "$1" = "where" ] && exit 0
      case "$*" in
        *--version*) exit 0 ;;
        *"exec rails-mmd generate"*)
          mkdir -p tmp/rails_mmd
          cp "$RAILS_MMD_TEST_ROOT/fixtures/schemas/render_plan/valid/er.json" \
            tmp/rails_mmd/core.er.render_plan.json
          cp "$RAILS_MMD_TEST_ROOT/fixtures/schemas/render_plan/valid/class.json" \
            tmp/rails_mmd/core.class.render_plan.json
          printf 'not mermaid\n' > tmp/rails_mmd/core.er.mmd
          printf 'not mermaid\n' > tmp/rails_mmd/core.class.mmd
          exit 0 ;;
        *) exit 0 ;;
      esac
    SH
  end

  let(:missing_expected_diagnostics_asdf) do
    <<~'SH'
      [ "$1" = "where" ] && exit 0
      case "$*" in
        *--version*) exit 0 ;;
        *"exec rails-mmd generate"*)
          printf '%s\n' '[{"code":"ASSOCIATION_MACRO_OMITTED"}]' \
            > rails_mmd_expected_diagnostics.json
          mkdir -p tmp/rails_mmd
          cp "$RAILS_MMD_TEST_ROOT/fixtures/schemas/render_plan/valid/er.json" \
            tmp/rails_mmd/core.er.render_plan.json
          cp "$RAILS_MMD_TEST_ROOT/fixtures/schemas/render_plan/valid/class.json" \
            tmp/rails_mmd/core.class.render_plan.json
          printf '%s\n' \
            'erDiagram' \
            '  direction LR' \
            '  %% sanitized comment' \
            '  USER }o..|| ACCOUNT : account' \
            '  USER {' \
            '    bigint id PK' \
            '    bigint account_id FK' \
            '  }' \
            '  ACCOUNT {' \
            '    bigint id PK' \
            '  }' > tmp/rails_mmd/core.er.mmd
          printf '%s\n' \
            'classDiagram' \
            '  direction BT' \
            '  class ORDER' \
            '  class ACCOUNT' \
            '  ORDER "0..1" --> "0..*" ACCOUNT : billing_account' \
            > tmp/rails_mmd/core.class.mmd
          exit 0 ;;
        *) exit 0 ;;
      esac
    SH
  end

  let(:missing_expected_relationships_asdf) do
    missing_expected_diagnostics_asdf.sub(
      'mkdir -p tmp/rails_mmd',
      "printf '[]\\n' > rails_mmd_expected_diagnostics.json\n          mkdir -p tmp/rails_mmd"
    )
  end

  def missing_expected_polymorphic_groups_asdf
    relationships = JSON.generate([generic_expected_relationship])
    missing_expected_relationships_asdf.sub(
      'mkdir -p tmp/rails_mmd',
      "printf '%s\\n' '#{relationships}' > rails_mmd_expected_relationships.json\n          mkdir -p tmp/rails_mmd"
    )
  end

  def missing_expected_habtm_asdf
    relationships = [generic_expected_relationship, habtm_expected_relationship]
    missing_expected_relationships_asdf.sub(
      'mkdir -p tmp/rails_mmd',
      "printf '%s\\n' '#{JSON.generate(relationships)}' > rails_mmd_expected_relationships.json\n          " \
      'mkdir -p tmp/rails_mmd'
    )
  end

  def generic_expected_relationship
    {
      relationship_id: 'relationships/users/account', owner_safe_token: 'USER', target_safe_token: 'ACCOUNT',
      label: 'account', owner_cardinality: '0..many', target_cardinality: '1..1'
    }
  end

  def habtm_expected_relationship
    {
      relationship_id: 'relationships/authors/habtm/authors_tags/author_id/tags/tag_id',
      owner_safe_token: 'AUTHOR', target_safe_token: 'TAG', label: 'tags',
      owner_cardinality: '0..many', target_cardinality: '0..many'
    }
  end

  def run_matrix(path: ENV.fetch('PATH'), pair: nil)
    stdout, stderr, status = Open3.capture3(
      { 'PATH' => path, 'RAILS_MMD_MATRIX_PAIR' => pair, 'RAILS_MMD_TEST_ROOT' => Dir.pwd },
      'bundle', 'exec', 'rake', 'verify:rails_matrix'
    )
    { success: status.success?, stdout: stdout, stderr: stderr, output: stdout + stderr }
  end

  def rake_prerequisites
    stdout, = Open3.capture3('bundle', 'exec', 'rake', '--prereqs')
    stdout
  end

  def with_fake_asdf(script)
    Dir.mktmpdir('rails-matrix-bin') do |bin_dir|
      asdf = File.join(bin_dir, 'asdf')
      File.write(asdf, "#!/bin/sh\n#{script}\n")
      FileUtils.chmod('+x', asdf)
      yield "#{bin_dir}:#{ENV.fetch('PATH')}"
    end
  end

  it 'reports how to install a missing matrix Ruby version' do
    with_fake_asdf('exit 1') do |path|
      expect(run_matrix(path: path)).to include(success: false, output: include('asdf install ruby 4.0.6'))
    end
  end

  it 'reports how to install the required Bundler version for a matrix Ruby' do
    with_fake_asdf('[ "$1" = "where" ] && exit 0; exit 1') do |path|
      expect(run_matrix(path: path)).to include(success: false, output: include('gem install bundler -v 4.0.10'))
    end
  end

  it 'checks prerequisites only for the selected diagnostic pair' do
    with_fake_asdf(selected_pair_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1')

      expect(result[:output]).not_to include('Missing matrix Ruby 3.3.12')
    end
  end

  it 'rejects parseable render plans that violate the public artifact schema' do
    with_fake_asdf(invalid_artifact_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1')

      expect(result).to include(success: false, output: include('schema-invalid core.er.render_plan.json'))
    end
  end

  it 'rejects Mermaid that does not match its validated render plan' do
    with_fake_asdf(malformed_mermaid_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1')

      expect(result).to include(success: false, output: include('does not match core.er.render_plan.json'))
    end
  end

  it 'rejects generated diagnostics that do not match the real-app expectation' do
    with_fake_asdf(missing_expected_diagnostics_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1')

      expect(result).to include(success: false, output: include('diagnostics did not match expectation'))
    end
  end

  it 'rejects generated relationships that do not match the real-app expectation' do
    with_fake_asdf(missing_expected_relationships_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1')

      expect(result).to include(success: false, output: include('relationships did not match expectation'))
    end
  end

  it 'rejects generated polymorphic groups that do not match the real-app expectation' do
    with_fake_asdf(missing_expected_polymorphic_groups_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1')

      expect(result).to include(success: false, output: include('polymorphic groups did not match expectation'))
    end
  end

  it 'rejects artifacts whose only missing expected relationship is HABTM' do
    with_fake_asdf(missing_expected_habtm_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1')

      expect(result).to include(success: false, output: include('relationships did not match expectation'))
    end
  end

  it 'runs the Rails matrix from the default local verification gate' do
    expect(rake_prerequisites).to match(/rake default\n(?: {4}.+\n)* {4}verify:rails_matrix/)
  end
end
# rubocop:enable RSpec/DescribeClass
