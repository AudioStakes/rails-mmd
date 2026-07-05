# frozen_string_literal: true

require 'open3'
require 'json'
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
        turbo\.json|lerna\.json|tsconfig(?:\.[^/]+)?\.json|[^/]+\.(?:d\.)?(?:ts|tsx|mts|cts)
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

  def hosted_github_action_workflow_files
    git_files.grep(%r{\A\.github/workflows/[^/]+\.ya?ml\z})
  end

  def github_actions_dependabot_entries
    return [] unless File.exist?('.github/dependabot.yml')

    config = YAML.safe_load_file('.github/dependabot.yml')
    Array(config.fetch('updates', [])).select do |entry|
      entry.fetch('package-ecosystem') == 'github-actions'
    end
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

  it 'keeps hosted GitHub Actions workflow files untracked' do
    expect(hosted_github_action_workflow_files).to be_empty
  end

  it 'keeps Dependabot from managing GitHub Actions dependencies' do
    expect(github_actions_dependabot_entries).to be_empty
  end

  it 'keeps new RuboCop cops enabled' do
    config = YAML.safe_load_file('.rubocop.yml')

    expect(config.fetch('AllCops').fetch('NewCops')).to eq('enable')
  end

  it 'keeps P0-excluded CLI terms out of help' do
    normalized_help = help_output.downcase

    expect(excluded_help_terms.select { |term| normalized_help.include?(term) }).to be_empty
  end

  it 'keeps generate routed to the P0 implementation slice' do
    expect(generate_guard_result).to eq(expected_generate_guard_result)
  end

  it 'documents the generate guard release condition' do
    text = repository_text('docs/development/setup-guards.md')

    expect(text).to include('rails-mmd generate guard release condition')
  end

  it 'preserves required P0 contract sections' do
    text = repository_text('docs/p0-contract.md')

    expect(text).to include_required_contract_sections
  end

  it 'documents user-facing generate behavior from the README' do
    readme = repository_text('README.md')

    expect(readme).to include('docs/usage.md', 'docs/p0-blocking-fixture-matrix.md')
  end

  it 'keeps the P0 blocking fixture matrix aligned with blocking diagnostics' do
    text = repository_text('docs/p0-blocking-fixture-matrix.md')

    expect(blocking_diagnostic_codes - documented_codes(text)).to be_empty
  end

  it 'documents the P0 user-facing exit codes' do
    text = repository_text('docs/usage.md')

    expect(user_facing_exit_codes(text)).to include('0', '1', '2', '3', '4', '99')
  end

  it 'documents superseded invalid issues 1 through 6' do
    text = repository_text('docs/issue-administration.md')

    expect(superseded_issue_numbers(text)).to eq((1..6).to_a)
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

  def generate_guard_result
    stdout, stderr, status = run_cli('generate')

    {
      'command_defined' => RailsMmd::CLI.commands.key?('generate'),
      'success' => status.success?,
      'stdout' => stdout,
      'stderr_code' => JSON.parse(stderr).fetch('diagnostics').first.fetch('code')
    }
  end

  def expected_generate_guard_result
    {
      'command_defined' => true,
      'success' => false,
      'stdout' => '',
      'stderr_code' => 'CONFIG_NOT_FOUND'
    }
  end

  def blocking_diagnostic_codes
    config_blocking_codes + domain_blocking_codes + runtime_blocking_codes + publish_blocking_codes
  end

  def config_blocking_codes
    %w[CONFIG_NOT_FOUND CONFIG_SCHEMA_INVALID CONFIG_DOMAIN_NOT_FOUND OUTPUT_DIRECTORY_INVALID]
  end

  def domain_blocking_codes
    %w[DOMAIN_MODEL_NOT_FOUND DOMAIN_MODEL_NOT_RENDERABLE DOMAIN_EMPTY]
  end

  def runtime_blocking_codes
    %w[RAILS_LOAD_FAILED RAILS_EAGER_LOAD_FAILED MULTI_DB_UNSUPPORTED MODEL_TABLE_MISSING
       MODEL_PRIMARY_KEY_UNSUPPORTED SAFE_TOKEN_COLLISION MERMAID_SERIALIZATION_FAILED]
  end

  def publish_blocking_codes
    %w[OUTPUT_WRITE_FAILED INTERNAL_ERROR]
  end

  def documented_codes(text)
    text.scan(/`([A-Z0-9_]+)`/).flatten
  end

  def user_facing_exit_codes(text)
    text.scan(/^\| (\d+) \|/).flatten
  end

  def superseded_issue_numbers(text)
    return [] unless text.match?(/superseded/i)

    text.scan(/#(\d+)\b/).flatten.map(&:to_i).grep(1..6).uniq.sort
  end
end
# rubocop:enable RSpec/DescribeClass
