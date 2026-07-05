# frozen_string_literal: true

require 'tmpdir'
require 'rails_mmd/canonical_json'
require 'rails_mmd/rails_loader'
require 'rails_mmd/schema_validator'

# rubocop:disable RSpec/ExampleLength, RSpec/InstanceVariable, RSpec/MultipleExpectations
RSpec.describe RailsMmd::RailsLoader do
  around do |example|
    Dir.mktmpdir do |root|
      @project_root = Pathname(root)
      project_root.join('config').mkpath
      example.run
    end
  end

  let(:project_root) { @project_root }

  it 'loads the Rails environment from the project root and eager-loads the application' do
    kernel = Class.new do
      attr_reader :loaded_path

      def load(path)
        @loaded_path = path
      end
    end.new
    application = Class.new do
      attr_reader :eager_loaded

      def eager_load!
        @eager_loaded = true
      end
    end.new
    rails = Struct.new(:application).new(application)

    result = described_class.new(project_root: project_root, kernel: kernel, rails_provider: -> { rails }).boot

    expect(result).to be_success
    expect(kernel.loaded_path).to eq(project_root.join('config/environment.rb').to_s)
    expect(result.application).to be(application)
    expect(application.eager_loaded).to be(true)
  end

  it 'requires execution inside the target application bundle when a Gemfile exists' do
    project_root.join('Gemfile').write("source 'https://rubygems.org'\n")
    outside_bundle = Struct.new(:default_gemfile).new(project_root.parent.join('Gemfile'))

    result = described_class.new(
      project_root: project_root,
      kernel: Class.new { def load(_path) = raise('must not load') }.new,
      bundler: outside_bundle
    ).boot

    expect(result).not_to be_success
    expect(result.diagnostics.first).to include('code' => 'RAILS_LOAD_FAILED')
    expect(result.diagnostics.first.fetch('metadata')).to include(
      'exception_class' => 'RailsMmd::RailsLoader::BundleContextError',
      'backtrace' => nil
    )
    expect_schema_valid_diagnostic(result.diagnostics.first)
  end

  it 'fails closed when a target Gemfile exists without a Bundler context' do
    project_root.join('Gemfile').write("source 'https://rubygems.org'\n")

    result = described_class.new(
      project_root: project_root,
      kernel: Class.new do
        def load(_path) = raise('must not load')
      end.new,
      bundler: nil
    ).boot

    expect(result).not_to be_success
    expect(result.diagnostics.first).to include('code' => 'RAILS_LOAD_FAILED')
    expect(result.diagnostics.first.fetch('metadata'))
      .to include('exception_class' => 'RailsMmd::RailsLoader::BundleContextError')
    expect_schema_valid_diagnostic(result.diagnostics.first)
  end

  it 'fails closed when Bundler cannot identify the current Gemfile' do
    project_root.join('Gemfile').write("source 'https://rubygems.org'\n")
    missing_bundle = Class.new do
      def default_gemfile
        raise Bundler::GemfileNotFound
      end
    end.new

    result = described_class.new(
      project_root: project_root,
      kernel: Class.new do
        def load(_path) = raise('must not load')
      end.new,
      bundler: missing_bundle
    ).boot

    expect(result).not_to be_success
    expect(result.diagnostics.first).to include('code' => 'RAILS_LOAD_FAILED')
    expect(result.diagnostics.first.fetch('metadata'))
      .to include('exception_class' => 'RailsMmd::RailsLoader::BundleContextError')
    expect_schema_valid_diagnostic(result.diagnostics.first)
  end

  it 'returns a schema-valid RAILS_LOAD_FAILED diagnostic for boot failures' do
    kernel = Class.new do
      def load(_path)
        raise 'secret=/Users/dev/app failed'
      end
    end.new

    result = described_class.new(project_root: project_root, kernel: kernel).boot

    expect(result).not_to be_success
    expect(result.exit_code).to eq(2)
    expect(result.diagnostics.first).to include('code' => 'RAILS_LOAD_FAILED')
    expect(result.diagnostics.first.fetch('metadata')).to include(
      'exception_class' => 'RuntimeError',
      'backtrace' => nil
    )
    expect(result.diagnostics.first.fetch('metadata').fetch('exception_summary')).not_to include('/Users/dev/app')
    expect_schema_valid_diagnostic(result.diagnostics.first)
  end

  it 'returns RAILS_LOAD_FAILED for load and syntax errors' do
    [LoadError, SyntaxError].each do |error_class|
      kernel = Class.new do
        define_method(:load) do |_path|
          raise error_class, '/Users/dev/app failed'
        end
      end.new

      result = described_class.new(project_root: project_root, kernel: kernel).boot

      expect(result).not_to be_success
      expect(result.diagnostics.first).to include('code' => 'RAILS_LOAD_FAILED')
      expect(result.diagnostics.first.fetch('metadata').fetch('exception_summary')).not_to include('/Users/dev')
      expect_schema_valid_diagnostic(result.diagnostics.first)
    end
  end

  it 'returns a schema-valid RAILS_EAGER_LOAD_FAILED diagnostic for eager-load failures' do
    application = Class.new do
      def eager_load!
        raise 'password=/tmp/app failed'
      end
    end.new
    rails = Struct.new(:application).new(application)

    result = described_class.new(
      project_root: project_root,
      kernel: Class.new { def load(_path); end }.new,
      rails_provider: -> { rails }
    ).boot

    expect(result).not_to be_success
    expect(result.exit_code).to eq(2)
    expect(result.diagnostics.first).to include('code' => 'RAILS_EAGER_LOAD_FAILED')
    expect(result.diagnostics.first.fetch('metadata')).to include(
      'exception_class' => 'RuntimeError',
      'backtrace' => nil
    )
    expect(result.diagnostics.first.fetch('metadata').fetch('exception_summary')).not_to include('/tmp/app')
    expect_schema_valid_diagnostic(result.diagnostics.first)
  end

  it 'returns RAILS_EAGER_LOAD_FAILED when eager_load! is unavailable' do
    rails = Struct.new(:application).new(Object.new)

    result = described_class.new(
      project_root: project_root,
      kernel: Class.new { def load(_path); end }.new,
      rails_provider: -> { rails }
    ).boot

    expect(result).not_to be_success
    expect(result.diagnostics.first).to include('code' => 'RAILS_EAGER_LOAD_FAILED')
    expect_schema_valid_diagnostic(result.diagnostics.first)
  end

  it 'returns RAILS_EAGER_LOAD_FAILED for eager-load load errors' do
    application = Class.new do
      def eager_load!
        raise LoadError, '/Users/dev/eager failed'
      end
    end.new
    rails = Struct.new(:application).new(application)

    result = described_class.new(
      project_root: project_root,
      kernel: Class.new { def load(_path); end }.new,
      rails_provider: -> { rails }
    ).boot

    expect(result).not_to be_success
    expect(result.diagnostics.first).to include('code' => 'RAILS_EAGER_LOAD_FAILED')
    expect(result.diagnostics.first.fetch('metadata').fetch('exception_summary')).not_to include('/Users/dev')
    expect_schema_valid_diagnostic(result.diagnostics.first)
  end

  def expect_schema_valid_diagnostic(diagnostic)
    envelope = {
      'schema_version' => 1,
      'scope' => 'global',
      'domain_id' => nil,
      'diagnostics' => [diagnostic],
      'digest_sha256' => RailsMmd::CanonicalJson.digest_sha256(diagnostic)
    }

    expect(RailsMmd::SchemaValidator.new.valid?(:diagnostics, envelope)).to be(true)
  end
end
# rubocop:enable RSpec/ExampleLength, RSpec/InstanceVariable, RSpec/MultipleExpectations
