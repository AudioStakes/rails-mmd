# frozen_string_literal: true

require 'open3'
require 'json'
require 'rails_mmd/exit_policy'
require 'yaml'

# rubocop:disable-next RSpec/DescribeClass
RSpec.describe 'repository drift guards' do
  def git_files
    stdout, stderr, status = Open3.capture3('git', 'ls-files')
    raise stderr unless status.success?

    stdout.lines.map(&:chomp).select { |path| File.file?(path) }
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

  def runtime_mermaid_cli_references
    paths = git_files.grep(%r{\A(?:lib/|exe/|Gemfile(?:\.lock)?\z|rails-mmd\.gemspec\z|Rakefile\z)})
    paths.select { |path| File.read(path).match?(%r{mermaid-cli|@mermaid-js/mermaid-cli|\bmmdc\b}i) }
  end

  def github_actions_dependabot_entries
    return [] unless File.exist?('.github/dependabot.yml')

    config = YAML.safe_load_file('.github/dependabot.yml')
    Array(config.fetch('updates', [])).select do |entry|
      entry.fetch('package-ecosystem') == 'github-actions'
    end
  end

  it 'keeps the repository free of Node and TypeScript workspace files' do
    expect(git_files.grep(node_typescript_pattern)).to be_empty
  end

  it 'keeps Mermaid CLI out of runtime code and dependency files' do
    expect(runtime_mermaid_cli_references).to be_empty
  end

  it 'rejects RuboCop baseline files' do
    expect(git_files.grep(%r{(^|/)\.?rubocop[_-]todo\.(?:yml|yaml)\z})).to be_empty
  end

  it 'keeps hosted GitHub Actions workflow files untracked' do
    expect(git_files.grep(%r{\A\.github/workflows/[^/]+\.ya?ml\z})).to be_empty
  end

  it 'keeps Dependabot from managing GitHub Actions dependencies' do
    expect(github_actions_dependabot_entries).to be_empty
  end

  it 'keeps new RuboCop cops enabled' do
    config = YAML.safe_load_file('.rubocop.yml')

    expect(config.fetch('AllCops').fetch('NewCops')).to eq('enable')
  end

  it 'links current usage, support, contract, and verification documentation from the README' do
    expect(File.read('README.md')).to include(
      'docs/usage.md', 'docs/active-record-association-support.md',
      'docs/contract.md', 'docs/development/testing.md'
    )
  end

  it 'documents every diagnostic default from the runtime catalog' do
    expect(documented_diagnostic_defaults).to eq(JSON.parse(File.read('schemas/diagnostic_defaults.json')))
  end

  it 'keeps documented diagnostic exit codes aligned with the process exit policy' do
    diagnostic_catalog_rows.each do |cells|
      expect(cells[2]).to eq(diagnostic_exit_codes(cells))
    end
  end

  it 'documents the user-facing exit codes' do
    expect(user_facing_exit_rows).to eq(expected_user_facing_exit_rows)
  end

  def diagnostic_catalog_rows
    File.foreach('docs/contract.md').filter_map do |line|
      cells = markdown_table_cells(line)
      cells if cells&.first&.match?(/\A`[A-Z0-9_]+`\z/)
    end
  end

  def documented_diagnostic_defaults
    diagnostic_catalog_rows.to_h do |cells|
      [cells[0].delete('`'), {
        'severity' => cells[1].split(' or ').first,
        'phase' => cells[3],
        'scope' => cells[4]
      }]
    end
  end

  def diagnostic_exit_codes(cells)
    cells[1].split(' or ').map do |severity|
      RailsMmd::ExitPolicy.exit_code([{ 'code' => cells[0].delete('`'), 'severity' => severity }]).to_s
    end.join(' or ')
  end

  def markdown_table_cells(line)
    return unless line.start_with?('|')

    line.split('|')[1..-2]&.map(&:strip)
  end

  def user_facing_exit_rows
    File.foreach('docs/usage.md').filter_map do |line|
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
end
