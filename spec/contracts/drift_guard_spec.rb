# frozen_string_literal: true

require 'open3'
require 'rails_mmd/cli'
require 'yaml'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'repository drift guards' do
  def allowed_node_typescript_files
    []
  end

  def git_files
    stdout, stderr, status = Open3.capture3('git', 'ls-files')
    raise stderr unless status.success?

    stdout.lines.map(&:chomp)
  end

  def repository_text(path)
    File.read(path)
  end

  def run_cli(*)
    Open3.capture3('bundle', 'exec', 'exe/rails-mmd', *)
  end

  def forbidden_node_typescript_files
    git_files.grep(node_typescript_pattern) - allowed_node_typescript_files
  end

  def node_typescript_pattern
    %r{
      (^|/)
      (
        package\.json|package-lock\.json|npm-shrinkwrap\.json|yarn\.lock|
        pnpm-lock\.yaml|pnpm-workspace\.yaml|\.yarnrc\.yml|nx\.json|
        turbo\.json|lerna\.json|tsconfig(?:\.[^/]+)?\.json|[^/]+\.(?:ts|tsx|mts|cts)
      )$
    }x
  end

  def runtime_dependency_files
    git_files.grep(%r{\A(?:lib/|exe/|Gemfile(?:\.lock)?\z|rails_mmd\.gemspec\z|Rakefile\z)})
  end

  def runtime_mermaid_cli_references
    runtime_dependency_files.select do |path|
      repository_text(path).match?(%r{mermaid-cli|@mermaid-js/mermaid-cli|\bmmdc\b}i)
    end
  end

  def rubocop_baseline_files
    git_files.grep(%r{(^|/)\.?rubocop[_-]todo\.(?:yml|yaml)\z})
  end

  def help_output
    stdout, = run_cli('--help')
    stdout
  end

  def excluded_help_terms
    [
      '.erdconfig', 'depth', 'glob', 'regex', 'compatibility', 'cache',
      'mermaid cli', 'validate', 'attributes all', 'attributes content',
      'unique-key'
    ]
  end

  it 'keeps Node and TypeScript workspace files behind an explicit allowlist' do
    expect(forbidden_node_typescript_files).to be_empty
  end

  it 'keeps Mermaid CLI out of runtime code and dependency files' do
    expect(runtime_mermaid_cli_references).to be_empty
  end

  it 'rejects RuboCop baseline files' do
    expect(rubocop_baseline_files).to be_empty
  end

  it 'keeps new RuboCop cops enabled' do
    config = YAML.safe_load_file('.rubocop.yml')

    expect(config.fetch('AllCops').fetch('NewCops')).to eq('enable')
  end

  it 'keeps P0-excluded CLI terms out of help' do
    normalized_help = help_output.downcase

    expect(excluded_help_terms.select { |term| normalized_help.include?(term) }).to be_empty
  end

  it 'keeps generate unroutable until the P0 implementation slice lands' do
    stdout, stderr, status = run_cli('generate')

    expect([RailsMmd::CLI.commands.key?('generate'), status.success?, stdout, stderr])
      .to eq([false, false, '', "Could not find command \"generate\".\n"])
  end

  it 'documents the generate guard release condition' do
    text = repository_text('docs/development/setup-guards.md')

    expect(text).to include('rails-mmd generate guard release condition')
  end

  it 'preserves required P0 contract sections' do
    text = repository_text('docs/p0-contract.md')

    expect(text).to include_required_contract_sections
  end

  it 'documents superseded invalid issues 1 through 6' do
    text = repository_text('docs/issue-administration.md')

    expect((1..6).reject { |number| text.include?("##{number}") }).to be_empty
  end

  it 'documents the future P0 sequence without implementing it' do
    text = repository_text('docs/development/setup-guards.md')

    expect(text).to include('1. Config loader and schema validation.', '13. CLI integration.')
  end

  matcher :include_required_contract_sections do
    match do |text|
      required_contract_sections.all? { |section| text.include?(section) }
    end

    def required_contract_sections
      [
        '## Supported Scope',
        '## Excluded Scope',
        '## Redaction',
        'Diagnostic catalog:',
        '## Artifacts And Publishing',
        'Atomic publish policy:'
      ]
    end
  end
end
# rubocop:enable RSpec/DescribeClass
