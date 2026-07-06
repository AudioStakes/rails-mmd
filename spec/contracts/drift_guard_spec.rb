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

    expect(blocking_matrix_rows(text)).to eq(blocking_diagnostic_rows)
  end

  it 'documents the P0 user-facing exit codes' do
    text = repository_text('docs/usage.md')

    expect(user_facing_exit_rows(text)).to eq(expected_user_facing_exit_rows)
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
    blocking_diagnostic_rows.keys
  end

  def blocking_diagnostic_rows
    diagnostic_catalog_rows.select { |_, row| blocking_exit_code?(row.fetch('exit')) }
  end

  def blocking_exit_code?(exit_code)
    exit_code.split(/\s+or\s+/).intersect?(%w[2 3 4 99])
  end

  def diagnostic_catalog_rows
    repository_text('docs/p0-contract.md').lines.filter_map do |line|
      cells = markdown_table_cells(line)
      next unless cells&.first&.match?(/\A`[A-Z0-9_]+`\z/)

      [cells[0].delete('`'), contract_policy_row(cells)]
    end.to_h
  end

  def contract_policy_row(cells)
    {
      'exit' => cells[2],
      'attachment' => cells[5],
      'publication_effect' => cells[6]
    }
  end

  def blocking_matrix_rows(text)
    text.lines.filter_map do |line|
      cells = markdown_table_cells(line)
      next unless cells&.first&.match?(/\A`[A-Z0-9_]+`\z/)

      [cells[0].delete('`'), matrix_policy_row(cells)]
    end.to_h
  end

  def matrix_policy_row(cells)
    {
      'exit' => cells[3],
      'attachment' => cells[4],
      'publication_effect' => cells[5]
    }
  end

  def markdown_table_cells(line)
    return unless line.start_with?('|')

    line.split('|')[1..-2]&.map(&:strip)
  end

  def user_facing_exit_rows(text)
    text.lines.filter_map do |line|
      cells = markdown_table_cells(line)
      [cells[0], cells[1]] if cells&.first&.match?(/\A\d+\z/)
    end.to_h
  end

  def expected_user_facing_exit_rows
    {
      '0' => 'success, including warning diagnostics when `--fail-on-warning` is absent',
      '1' => 'warning diagnostics were present and `--fail-on-warning` was set',
      '2' => 'config, output setup, Rails boot, domain, or schema probe error',
      '3' => 'Mermaid serialization failure or unresolved safe-token collision',
      '4' => 'output write or atomic publish failure',
      '99' => 'internal error'
    }
  end

  def superseded_issue_numbers(text)
    return [] unless text.match?(/superseded/i)

    text.scan(/#(\d+)\b/).flatten.map(&:to_i).grep(1..6).uniq.sort
  end
end
# rubocop:enable RSpec/DescribeClass
