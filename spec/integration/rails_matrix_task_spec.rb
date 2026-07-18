# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'tmpdir'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'the Rails compatibility matrix Rake command' do
  let(:invalid_artifact_asdf) do
    <<~SH
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
    <<~SH
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

  it 'executes every required Ruby and Rails pair' do
    expect(run_matrix).to include(success: true, stderr: '', stdout: include('PASS 3/3 Rails matrix pairs'))
  end

  it 'runs the Rails matrix from the default local verification gate' do
    expect(rake_prerequisites).to match(/rake default\n(?: {4}.+\n)* {4}verify:rails_matrix/)
  end
end
# rubocop:enable RSpec/DescribeClass
